import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

async function provisioningFixture() {
 const f=await fixture();
 await f.db.exec(`
 ALTER TABLE auth.users ADD COLUMN email text, ADD COLUMN email_confirmed_at timestamptz,
 ADD COLUMN deleted_at timestamptz, ADD COLUMN banned_until timestamptz;
 CREATE TABLE public.profiles(id uuid PRIMARY KEY,email text NOT NULL,name text NOT NULL,
 phone text,roll_number text,college text,branch text,year text,
 role text NOT NULL DEFAULT 'member',status text NOT NULL DEFAULT 'active',suspended_until timestamptz,
 is_registered boolean NOT NULL DEFAULT false,is_iste_member boolean NOT NULL DEFAULT false,
 is_sudo boolean NOT NULL DEFAULT false,is_primary_chairman boolean NOT NULL DEFAULT false,
 is_budget_activated boolean NOT NULL DEFAULT false,permissions jsonb NOT NULL DEFAULT '{}',
 updated_at timestamptz DEFAULT now());
 `);
 await f.db.exec(await readFile(new URL('../profile-provisioning.candidate.sql',import.meta.url),'utf8'));
 const {rows:[account]}=await f.db.query("INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(gen_random_uuid(),'signup@example.invalid',now()) RETURNING id");
 const details={name:'Test Signup',phone:'9876543210',roll_number:'TEST001',college:'Test College',branch:'CS',academic_year:'2'};
 const provision=async(fields=details,role='service_role')=>{
 await f.db.exec('SET ROLE '+role);
 try{return (await f.db.query("SELECT public.provision_verified_member($1,$2) result",[account.id,JSON.stringify(fields)])).rows[0].result;}
 finally{await f.db.exec('RESET ROLE');}
 };
 return {...f,account,details,provision};
}
test('verified signup provisions ordinary profile without memberships or privilege escalation',async()=>{
 const f=await provisioningFixture();try {
 const result=await f.provision();await f.provision();
 assert.equal(result.auth_user_id,f.account.id);
 const {rows:[p]}=await f.db.query("SELECT role,is_sudo,is_iste_member,permissions FROM public.profiles WHERE id=$1",[f.account.id]);
 assert.deepEqual(p,{role:'member',is_sudo:false,is_iste_member:false,permissions:{}});
 assert.equal((await f.db.query("SELECT count(*)::int n FROM unified_next.users WHERE auth_user_id=$1",[f.account.id])).rows[0].n,1);
 assert.equal((await f.db.query("SELECT count(*)::int n FROM unified_next.iste_members WHERE user_id=$1",[result.user_id])).rows[0].n,0);
 }finally{await f.db.close();}
});
test('unverified, banned and injected role inputs fail closed',async()=>{
 const f=await provisioningFixture();try {
 await assert.rejects(f.provision({...f.details,role:'chairman'}),/Unsupported/);
 await assert.rejects(f.provision({...f.details,branch:''}),/Complete valid/);
 await assert.rejects(f.provision(f.details,'authenticated'),/permission denied/);
 await f.db.query("UPDATE auth.users SET email_confirmed_at=NULL WHERE id=$1",[f.account.id]);
 await assert.rejects(f.provision(),/Verified active/);
 await f.db.query("UPDATE auth.users SET email_confirmed_at=now(),banned_until=now()+interval '1 day' WHERE id=$1",[f.account.id]);
 await assert.rejects(f.provision(),/Verified active/);
 assert.equal((await f.db.query("SELECT count(*)::int n FROM public.profiles")).rows[0].n,0);
 }finally{await f.db.close();}
});
test('matching legacy email never causes profile UUID rewrite',async()=>{
 const f=await provisioningFixture();try {
 const {rows:[old]}=await f.db.query("INSERT INTO public.profiles(id,email,name,role) VALUES(gen_random_uuid(),'signup@example.invalid','Existing','chairman') RETURNING id");
 await assert.rejects(f.provision(),/reconciliation/);
 const {rows:[p]}=await f.db.query("SELECT id,role FROM public.profiles");
 assert.equal(p.id,old.id);assert.equal(p.role,'chairman');
 }finally{await f.db.close();}
});
test('canonical identity keeps its stable ID when verified Auth identity is attached',async()=>{
 const f=await provisioningFixture();try {
 const {rows:[existing]}=await f.db.query("INSERT INTO unified_next.users(email,full_name) VALUES('signup@example.invalid','Staged User') RETURNING id");
 const result=await f.provision();
 assert.equal(result.user_id,existing.id);assert.notEqual(result.user_id,f.account.id);
 assert.equal((await f.db.query("SELECT auth_user_id FROM unified_next.users WHERE id=$1",[existing.id])).rows[0].auth_user_id,f.account.id);
 }finally{await f.db.close();}
});
test('an explicit denial or expired reviewer term overrides approval',async()=>{
 const f=await fixture();try {
 const id=await f.insert();
 await f.db.exec("UPDATE unified_next.execom_permissions SET allowed=false");
 await assert.rejects(f.call(id),/Not authorized/);
 await f.db.exec("UPDATE unified_next.execom_permissions SET allowed=true; UPDATE unified_next.execom_members SET starts_on=current_date-10,ends_on=current_date-1");
 await assert.rejects(f.call(id),/Not authorized/);
 }finally{await f.db.close();}
});


export async function fixture() {
 const db=new PGlite();
 try {
 await db.exec("CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role BYPASSRLS; CREATE SCHEMA auth; CREATE TABLE auth.users(id uuid PRIMARY KEY);");
 await db.exec(await readFile(new URL('../unified-schema.applied.sql',import.meta.url),'utf8'));
 const backfill=await readFile(new URL('../membership-backfill.sql',import.meta.url),'utf8');
 await db.exec(backfill.slice(0,backfill.indexOf('CREATE TEMP TABLE import_sources'))+'COMMIT;');
 const intake=await readFile(new URL('../../../../iste/supabase/migrations/20260923_membership_registrations.sql',import.meta.url),'utf8');
 await db.exec(intake.slice(0,intake.indexOf('insert into storage.buckets')));
 await db.exec(await readFile(new URL('../membership-approval.candidate.sql',import.meta.url),'utf8'));
 const {rows:[actor]}=await db.query("INSERT INTO auth.users VALUES(gen_random_uuid()) RETURNING id");
 const {rows:[user]}=await db.query("INSERT INTO unified_next.users(auth_user_id,email,full_name,account_status) VALUES($1,'reviewer@example.invalid','Test Reviewer','active') RETURNING id",[actor.id]);
 await db.query("INSERT INTO unified_next.iste_members(user_id,membership_id,status) VALUES($1,'KE104001','active')",[user.id]);
 const {rows:[appointment]}=await db.query("INSERT INTO unified_next.execom_members(user_id,tier,position,scope_code,term_label,starts_on,ends_on,status,approved_by,approved_at) VALUES($1,2,'NDC reviewer','organization','TEST',current_date-1,current_date+30,'active',$2,now()) RETURNING id",[user.id,actor.id]);
 await db.query("INSERT INTO unified_next.execom_permissions(assignment_id,permission_code,scope_code,allowed,changed_by,status) VALUES($1,'membership.approve','organization',true,$2,'approved')",[appointment.id,actor.id]);
 const insert=async(email='new@example.invalid',forums=[],fee=649,total=649)=>{
 const {rows:[r]}=await db.query("INSERT INTO public.membership_registrations(full_name,date_of_birth,academic_year,branch,phone,email,membership_fee,forums,total_amount,transaction_id,receipt_path) VALUES('Test Applicant','2004-02-29','2','Computer Science','9876543210',$1,$2,$3,$4,gen_random_uuid()::text,'test-only.pdf') RETURNING id",[email,fee,JSON.stringify(forums),total]); return r.id;};
 const call=async(id,memberId='KE104002',reviewer=actor.id,role='service_role')=>{
 await db.exec('SET ROLE '+role);
 try {return (await db.query("SELECT public.approve_membership_registration($1,$2,$3) result",[id,memberId,reviewer])).rows[0].result;}
 finally{await db.exec('RESET ROLE');}
 };
 return {db,actor,user,appointment,insert,call};
 } catch(error) { await db.close(); throw error; }
}
test('atomic approval, official ID, duration, forums and idempotent retry',async()=>{
 const f=await fixture(); try {
 const id=await f.insert('new@example.invalid',['SWaS Forum (299)','BITS Forum (129)'],1199,1328);
 const a=await f.call(id,' ke104002 ');
 assert.equal(a.status,'approved');assert.equal(a.membership_id,'KE104002');
 assert.deepEqual(await f.call(id),a);
 const {rows:[m]}=await f.db.query("SELECT m.*,u.account_status,u.auth_user_id FROM unified_next.iste_members m JOIN unified_next.users u ON u.id=m.user_id WHERE membership_id='KE104002'");
 assert.equal(m.duration_years,2); assert.deepEqual(m.forum_memberships,['BITS','SWAS']);
 assert.equal(m.account_status,'pending_review');assert.equal(m.auth_user_id,null);
 assert.equal((await f.db.query("SELECT count(*)::int n FROM unified_next.user_change_log")).rows[0].n,1);
 }finally{await f.db.close();}
});
test('anonymous/authenticated execution denied and unapproved reviewer denied',async()=>{
 const f=await fixture();try {
 const id=await f.insert();
 for(const role of ['anon','authenticated']) await assert.rejects(f.call(id,'KE104002',f.actor.id,role),/permission denied/);
 await f.db.exec("UPDATE unified_next.execom_permissions SET status='pending_review'");
 await assert.rejects(f.call(id),/Not authorized/);
 assert.equal((await f.db.query("SELECT status FROM public.membership_registrations WHERE id=$1",[id])).rows[0].status,'pending');
 }finally{await f.db.close();}
});
test('conflicts and malformed official ID leave registrations untouched',async()=>{
 const f=await fixture();try {
 const id=await f.insert();
 await assert.rejects(f.call(id,'ISTE-2026-0001'),/Official/);
 await assert.rejects(f.call(id,'KE104001'),/already allocated/);
 await f.call(id);
 const second=await f.insert('other@example.invalid');
 await assert.rejects(f.call(second),/already allocated/);
 await assert.rejects(f.call(id,'KE104003'),/already reviewed/);
 assert.equal((await f.db.query("SELECT count(*)::int n FROM unified_next.users WHERE email='other@example.invalid'")).rows[0].n,0);
 }finally{await f.db.close();}
});
test('duplicate forums and tampered totals rejected',async()=>{
 const f=await fixture();try {
 const dup=await f.insert('dup@example.invalid',['SWaS Forum (299)','SWaS Forum (299)'],1499,1499);
 await assert.rejects(f.call(dup),/duplicate forums/);
 const total=await f.insert('bad@example.invalid',['BITS Forum (129)'],649,649);
 await assert.rejects(f.call(total),/Payment total/);
 }finally{await f.db.close();}
});
test('failure late in allocation rolls back user, membership and intake',async()=>{
 const f=await fixture();try {
 const id=await f.insert();
 await f.db.exec("CREATE FUNCTION unified_next.test_fail_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'injected failure'; END $$; CREATE TRIGGER test_fail BEFORE INSERT ON unified_next.user_change_log FOR EACH ROW EXECUTE FUNCTION unified_next.test_fail_audit();");
 await assert.rejects(f.call(id),/injected failure/);
 assert.equal((await f.db.query("SELECT count(*)::int n FROM unified_next.users WHERE email='new@example.invalid'")).rows[0].n,0);
 assert.equal((await f.db.query("SELECT count(*)::int n FROM unified_next.iste_members WHERE membership_id='KE104002'")).rows[0].n,0);
 assert.equal((await f.db.query("SELECT status FROM public.membership_registrations WHERE id=$1",[id])).rows[0].status,'pending');
 }finally{await f.db.close();}
});
test('suspended target and suspended or expired reviewer cannot be approved',async()=>{
 const f=await fixture();try {
 const id=await f.insert();
 await f.db.exec("INSERT INTO unified_next.users(email,full_name,account_status) VALUES('new@example.invalid','Suspended','suspended')");
 await assert.rejects(f.call(id),/Account requires review/);
 await f.db.exec("UPDATE unified_next.users SET account_status='suspended' WHERE email='reviewer@example.invalid'");
 await assert.rejects(f.call(id),/Not authorized/);
 }finally{await f.db.close();}
});

