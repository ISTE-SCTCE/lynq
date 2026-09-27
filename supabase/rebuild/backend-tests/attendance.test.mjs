import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';

async function fixture() {
 const db=new PGlite();
 await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role BYPASSRLS;
 CREATE SCHEMA auth;
 CREATE TABLE auth.users(id uuid PRIMARY KEY,email text,email_confirmed_at timestamptz,deleted_at timestamptz,banned_until timestamptz);`);
 await db.exec(await readFile(new URL('../unified-schema.applied.sql',import.meta.url),'utf8'));
 const backfill=await readFile(new URL('../membership-backfill.sql',import.meta.url),'utf8');
 await db.exec(backfill.slice(0,backfill.indexOf('CREATE TEMP TABLE import_sources'))+'COMMIT;');
 await db.exec(`CREATE TABLE public.profiles(id uuid PRIMARY KEY,email text NOT NULL);
 CREATE TABLE public.events(id bigint PRIMARY KEY,num_days integer NOT NULL,attendance_finalized boolean);
 CREATE TABLE public.attendance(id bigserial PRIMARY KEY,event_id bigint REFERENCES public.events(id),
 user_id uuid REFERENCES public.profiles(id),scanned_by uuid REFERENCES public.profiles(id),day_number integer NOT NULL,
 UNIQUE(event_id,user_id,day_number));`);
 await db.exec(await readFile(new URL('../attendance.candidate.sql',import.meta.url),'utf8'));
 const person=async(email)=>{
  const {rows:[a]}=await db.query("INSERT INTO auth.users VALUES(gen_random_uuid(),$1,now(),NULL,NULL) RETURNING id",[email]);
  await db.query('INSERT INTO public.profiles VALUES($1,$2)',[a.id,email]);
  const {rows:[u]}=await db.query("INSERT INTO unified_next.users(auth_user_id,email,full_name,account_status) VALUES($1,$2,'Synthetic User','active') RETURNING id",[a.id,email]);
  return {auth:a.id,user:u.id};
 };
 const scanner=await person('scanner@example.invalid'); const attendee=await person('attendee@example.invalid');
 await db.query("INSERT INTO unified_next.iste_members(user_id,membership_id,status) VALUES($1,'KE104001','active')",[scanner.user]);
 const {rows:[assignment]}=await db.query("INSERT INTO unified_next.execom_members(user_id,tier,position,scope_code,term_label,starts_on,ends_on,status,approved_by,approved_at) VALUES($1,4,'chairperson','forum:bits','TEST',current_date-1,current_date+1,'active',$2,now()) RETURNING id",[scanner.user,scanner.auth]);
 await db.query("INSERT INTO unified_next.execom_permissions(assignment_id,permission_code,scope_code,allowed,status,changed_by) VALUES($1,'attendance.record','forum:bits',true,'approved',$2)",[assignment.id,scanner.auth]);
 await db.exec('INSERT INTO public.events VALUES(1,2,false),(2,1,false)');
 await db.query("INSERT INTO unified_next.attendance_event_config VALUES(1,'forum:bits','active_users',true,$1,now()),(2,'forum:swas','active_users',true,$1,now())",[scanner.auth]);
 const run=async(sql,args=[],role='service_role')=>{
  await db.exec('SET ROLE '+role);
  try{return (await db.query(sql,args)).rows[0]?.result;}finally{await db.exec('RESET ROLE');}
 };
 const issue=(event=1,day=1)=>run('SELECT public.issue_attendance_credential($1,$2,$3) result',[attendee.auth,event,day]);
 const scan=(token,event=1,day=1,actor=scanner.auth)=>run('SELECT public.record_event_attendance($1,$2,$3,$4) result',[actor,event,day,token]);
 return {db,scanner,attendee,assignment,run,issue,scan};
}

test('attendance uses canonical authorization but preserves legacy FK IDs and idempotent retry',async()=>{
 const f=await fixture();try {
 const token=await f.issue();const first=await f.scan(token.credential);assert.equal(first.status,'recorded');
 const retry=await f.scan(token.credential);assert.equal(retry.status,'already_recorded');assert.equal(retry.attendance_id,first.attendance_id);
 const {rows:[row]}=await f.db.query('SELECT user_id,scanned_by FROM public.attendance');
 assert.equal(row.user_id,f.attendee.auth);assert.equal(row.scanned_by,f.scanner.auth);assert.notEqual(f.attendee.auth,f.attendee.user);
 const {rows:[stored]}=await f.db.query('SELECT octet_length(credential_digest) bytes,consumed_at IS NOT NULL consumed FROM unified_next.attendance_credentials');
 assert.equal(stored.bytes,32);assert.equal(stored.consumed,true);
 }finally{await f.db.close();}
});
test('different valid days are separate; duplicate token stays unconsumed',async()=>{
 const f=await fixture();try {
 const first=await f.issue(); const duplicate=await f.issue();
 await f.scan(first.credential); assert.equal((await f.scan(duplicate.credential)).status,'already_recorded');
 const secondDay=await f.issue(1,2);await f.scan(secondDay.credential,1,2);
 assert.equal((await f.db.query('SELECT count(*)::int n FROM public.attendance')).rows[0].n,2);
 assert.equal((await f.db.query('SELECT count(*)::int n FROM unified_next.attendance_credentials WHERE consumed_at IS NULL')).rows[0].n,1);
 }finally{await f.db.close();}
});
test('denies anonymous invocation, wrong scope, pending approval, and finalized events',async()=>{
 const f=await fixture();try {
 await assert.rejects(f.run('SELECT public.issue_attendance_credential($1,1,1)',[f.attendee.auth],'anon'),/permission denied/);
 const other=await f.issue(2); await assert.rejects(f.scan(other.credential,2),/Not authorized/);
 const token=await f.issue();await f.db.exec("UPDATE unified_next.execom_permissions SET status='pending_review'");
 await assert.rejects(f.scan(token.credential),/Not authorized/);
 await f.db.exec('UPDATE public.events SET attendance_finalized=true WHERE id=1');
 await assert.rejects(f.issue(),/unavailable/);
 }finally{await f.db.close();}
});
test('credential is bound to event/day; rejects expiry, forged credentials and invalid day',async()=>{
 const f=await fixture();try {
 const token=await f.issue();await assert.rejects(f.scan(token.credential,1,2),/Invalid credential/);
 await assert.rejects(f.scan('a'.repeat(72)),/Invalid credential/);
 await assert.rejects(f.issue(1,3),/unavailable/);await assert.rejects(f.issue(1,0),/unavailable/);
 await f.db.exec("UPDATE unified_next.attendance_credentials SET expires_at=clock_timestamp()-interval '1 second'");
 await assert.rejects(f.scan(token.credential),/expired/);
 assert.equal((await f.db.query('SELECT count(*)::int n FROM public.attendance')).rows[0].n,0);
 }finally{await f.db.close();}
});
test('explicit eligible roster rechecked on scan, bans and identity mismatch fail closed',async()=>{
 const f=await fixture();try {
 await f.db.exec("UPDATE unified_next.attendance_event_config SET eligibility_mode='approved_attendees' WHERE event_id=1");
 await assert.rejects(f.issue(),/Not eligible/);
 await f.db.query('INSERT INTO unified_next.attendance_eligible_users VALUES(1,$1,$2,now())',[f.attendee.user,f.scanner.auth]);
 const token=await f.issue();await f.db.exec('DELETE FROM unified_next.attendance_eligible_users');
 await assert.rejects(f.scan(token.credential),/Not eligible/);
 await f.db.query("UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id=$1",[f.attendee.auth]);
 await assert.rejects(f.issue(),/Verified active/);
 await f.db.query("UPDATE auth.users SET banned_until=NULL,email='changed@example.invalid' WHERE id=$1",[f.attendee.auth]);
 await assert.rejects(f.issue(),/Verified active/);
 }finally{await f.db.close();}
});

test('approved explicit denial overrides an organization-wide allowance',async()=>{
 const f=await fixture();try {
 const token=await f.issue();
 const {rows:[assignment]}=await f.db.query("INSERT INTO unified_next.execom_members(user_id,tier,position,scope_code,term_label,starts_on,ends_on,status,approved_by,approved_at) VALUES($1,1,'society_chairperson','organization','TEST',current_date-1,current_date+1,'active',$2,now()) RETURNING id",[f.scanner.user,f.scanner.auth]);
 await f.db.query("INSERT INTO unified_next.execom_permissions(assignment_id,permission_code,scope_code,allowed,status,changed_by) VALUES($1,'attendance.record','organization',true,'approved',$2)",[assignment.id,f.scanner.auth]);
 await f.db.query('UPDATE unified_next.execom_permissions SET allowed=false WHERE assignment_id=$1',[f.assignment.id]);
 await assert.rejects(f.scan(token.credential),/Not authorized/);
 }finally{await f.db.close();}
});
test('legacy anonymous RPC/direct writes block activation; token failure rolls back check-in',async()=>{
 const f=await fixture();try {
 await f.db.exec('GRANT INSERT ON public.attendance TO authenticated');await assert.rejects(f.issue(),/cutover blocked/);
 await f.db.exec('REVOKE INSERT ON public.attendance FROM authenticated');
 await f.db.exec('CREATE FUNCTION public.mark_attendance_atomic() RETURNS boolean LANGUAGE sql AS $$ SELECT true $$');
 await assert.rejects(f.issue(),/cutover blocked/);
 await f.db.exec('REVOKE ALL ON FUNCTION public.mark_attendance_atomic() FROM PUBLIC,anon,authenticated');
 const token=await f.issue();
 await f.db.exec("CREATE FUNCTION unified_next.fail_consumption() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'injected token failure'; END $$; CREATE TRIGGER fail_consumption BEFORE UPDATE ON unified_next.attendance_credentials FOR EACH ROW EXECUTE FUNCTION unified_next.fail_consumption();");
 await assert.rejects(f.scan(token.credential),/injected token failure/);
 assert.equal((await f.db.query('SELECT count(*)::int n FROM public.attendance')).rows[0].n,0);
 assert.equal((await f.db.query('SELECT count(*)::int n FROM unified_next.attendance_credentials WHERE consumed_at IS NULL')).rows[0].n,1);
 }finally{await f.db.close();}
});
