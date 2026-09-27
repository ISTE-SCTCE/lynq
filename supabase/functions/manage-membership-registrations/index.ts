import { createClient } from 'npm:@supabase/supabase-js@2.57.4'

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return response({ error: 'Method not allowed' }, 405)

  const authorization = req.headers.get('Authorization')
  if (!authorization?.startsWith('Bearer ')) {
    return response({ error: 'Authentication is required.' }, 401)
  }

  const url = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const token = authorization.substring('Bearer '.length)
  const admin = createClient(url, serviceKey)
  const { data: userData, error: userError } = await admin.auth.getUser(token)
  if (userError || !userData.user || !userData.user.email_confirmed_at) return response({ error: 'A verified session is required.' }, 401)

  // Deployment requires membership-approval.candidate.sql plus approved canonical
  // reviewer appointments. Legacy editable profile roles are not authority.
  const { data: canReview, error: accessError } = await admin.rpc('can_approve_membership', {
    p_reviewer_id: userData.user.id,
  })
  if (accessError || canReview !== true) {
    return response({ error: 'You are not permitted to manage registrations.' }, 403)
  }

  const body = await req.json().catch(() => null)
  if (!body || typeof body.action !== 'string') return response({ error: 'Invalid request.' }, 400)

  if (body.action === 'list') {
    const { data: registrations, error } = await admin
      .from('membership_registrations')
      .select('id, full_name, email, phone, branch, academic_year, membership_fee, forums, total_amount, transaction_id, status, created_at')
      .order('created_at', { ascending: false })
    if (error) return response({ error: 'Unable to load registrations.' }, 500)

    const { data: count, error: countError } = await admin.rpc('count_approved_iste_members', {
      p_reviewer_id: userData.user.id,
    })
    if (countError) return response({ error: 'Unable to load member count.' }, 500)

    return response({ registrations, totalMembers: count ?? 0 })
  }

  if (body.action === 'review') {
    const registrationId = typeof body.registrationId === 'string' ? body.registrationId : ''
    const status = typeof body.status === 'string' ? body.status : ''
    if (!registrationId || !['approved', 'rejected'].includes(status)) {
      return response({ error: 'Invalid review request.' }, 400)
    }

    if (status === 'approved') {
      const membershipId = typeof body.membershipId === 'string'
        ? body.membershipId.trim().toUpperCase() : ''
      if (!/^KE104[0-9]{3}$/.test(membershipId)) {
        return response({ error: 'Enter the official KE104xxx membership ID before approving.' }, 400)
      }
      // Approval must allocate the membership and close the intake row in one
      // database transaction. Never fall back to a status-only approval.
      const { data, error } = await admin.rpc('approve_membership_registration', {
        p_registration_id: registrationId,
        p_membership_id: membershipId,
        p_reviewer_id: userData.user.id,
      })
      if (error) {
        return response({ error: 'Membership could not be allocated. The registration has not been approved; please contact the administrator.' }, 409)
      }
      if (!data || data.id !== registrationId || data.membership_id !== membershipId || data.status !== 'approved') {
        return response({ error: 'Approval could not be confirmed. Refresh the queue before retrying.' }, 502)
      }
      return response({ id: data.id, status: data.status, membershipId: data.membership_id })
    }

    const { data, error } = await admin
      .from('membership_registrations')
      .update({ status, reviewed_by: userData.user.id, reviewed_at: new Date().toISOString(), updated_at: new Date().toISOString() })
      .eq('id', registrationId)
      .eq('status', 'pending')
      .select('id')
      .maybeSingle()

    if (error) return response({ error: 'Unable to save review.' }, 500)
    if (!data) return response({ error: 'This registration has already been reviewed.' }, 409)
    return response({ id: data.id, status })
  }

  return response({ error: 'Unknown action.' }, 400)
})
