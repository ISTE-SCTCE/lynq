import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

const owner='10000000-0000-4000-8000-000000000001';
const other='10000000-0000-4000-8000-000000000002';
async function fixture() {
 const db=new PGlite();
 try {
 await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role BYPASSRLS;
 CREATE SCHEMA auth;
 CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 GRANT USAGE ON SCHEMA auth TO authenticated;
 CREATE TABLE auth.users(id uuid PRIMARY KEY,email text);
 CREATE TABLE public.profiles(id uuid PRIMARY KEY,email text,name text,phone text,roll_number text,
 branch text,year text,college text,fcm_token text,last_active timestamptz,last_seen timestamptz,
 role text DEFAULT 'member',permissions jsonb DEFAULT '{}',status text DEFAULT 'active',
 is_sudo boolean DEFAULT false,is_iste_member boolean DEFAULT false);
 CREATE VIEW public.users AS SELECT * FROM public.profiles;
 CREATE FUNCTION public.users_view_dml() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
 BEGIN UPDATE public.profiles SET role=NEW.role WHERE id=OLD.id; RETURN NEW; END $$;
 CREATE TRIGGER unsafe_view_write INSTEAD OF UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.users_view_dml();
 CREATE FUNCTION public.handle_auth_user_sync() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
 BEGIN UPDATE public.profiles SET id=NEW.id WHERE email=NEW.email; RETURN NEW; END $$;
 CREATE TRIGGER sync_user AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_auth_user_sync();
 CREATE FUNCTION public.provision_member(p_role text) RETURNS void LANGUAGE sql SECURITY DEFINER AS $$ UPDATE public.profiles SET role=p_role $$;
 CREATE FUNCTION public.verify_membership_status(p_email text) RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $$ SELECT true $$;
 GRANT ALL ON public.users,public.profiles TO anon,authenticated,service_role;
 GRANT UPDATE(role),INSERT(role) ON public.profiles,public.users TO authenticated;
 ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
 CREATE POLICY read_own ON public.profiles FOR SELECT TO authenticated USING(auth.uid()=id);
 CREATE POLICY old_permissive_update ON public.profiles FOR UPDATE TO authenticated USING(true) WITH CHECK(true);
 INSERT INTO public.profiles(id,email,name) VALUES('${owner}','owner@example.invalid','Owner'),('${other}','other@example.invalid','Other');
 `);
 await db.exec(await readFile(new URL('../legacy-identity-lockdown.candidate.sql',import.meta.url),'utf8'));
 await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[owner]);
 return db;
 }catch(e){await db.close();throw e;}
}
test('ordinary own-profile edits survive but identity and privileges cannot change',async()=>{
 const db=await fixture();try{
 await db.exec('SET ROLE authenticated');
 await db.query('UPDATE public.profiles SET name=$1 WHERE id=$2',['Updated',owner]);
 for(const field of ['id','email','role','permissions','status','is_sudo','is_iste_member']){
  await assert.rejects(db.exec(`UPDATE public.profiles SET ${field}=${field}`),/permission denied/);
 }
 await assert.rejects(db.exec("UPDATE public.users SET role='chairman'"),/permission denied/);
 await assert.rejects(db.exec("SELECT public.provision_member('chairman')"),/permission denied/);
 await assert.rejects(db.exec("SELECT public.verify_membership_status('owner@example.invalid')"),/permission denied/);
 await assert.rejects(db.exec("INSERT INTO public.profiles(role) VALUES('chairman')"),/permission denied/);
 await assert.rejects(db.exec('DELETE FROM public.profiles'),/permission denied/);
 await db.query('UPDATE public.profiles SET name=$1 WHERE id=$2',['Intruder',other]);
 await db.exec('RESET ROLE');
 assert.equal((await db.query('SELECT name FROM public.profiles WHERE id=$1',[owner])).rows[0].name,'Updated');
 assert.equal((await db.query('SELECT name FROM public.profiles WHERE id=$1',[other])).rows[0].name,'Other');
 }finally{await db.close();}
});
test('Auth insertion cannot rewrite a matching legacy profile ID',async()=>{
 const db=await fixture();try{
 await db.query("INSERT INTO auth.users(id,email) VALUES(gen_random_uuid(),'owner@example.invalid')");
 assert.equal((await db.query("SELECT id FROM public.profiles WHERE email='owner@example.invalid'")).rows[0].id,owner);
 const {rows:[fn]}=await db.query("SELECT prosecdef FROM pg_proc WHERE proname='handle_auth_user_sync'");
 assert.equal(fn.prosecdef,false);
 }finally{await db.close();}
});
test('anonymous writes fail; server provisioning privileges remain available',async()=>{
 const db=await fixture();try{
 await db.exec('SET ROLE anon');
 await assert.rejects(db.exec("UPDATE public.profiles SET name='Intruder'"),/permission denied/);
 await assert.rejects(db.exec("INSERT INTO public.users(role) VALUES('chairman')"),/permission denied/);
 await db.exec('RESET ROLE; SET ROLE service_role');
 await db.query("UPDATE public.profiles SET role='member' WHERE id=$1",[owner]);
 }finally{await db.close();}
});
