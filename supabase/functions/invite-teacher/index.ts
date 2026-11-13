import { withSupabase } from "npm:@supabase/server@1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: corsHeaders });

const handler = withSupabase({ auth: "user" }, async (req, ctx) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const callerId = ctx.userClaims?.sub;
    if (!callerId) return json({ error: "Authentication required" }, 401);

    const { data: staff, error: staffError } = await ctx.supabase
      .from("admin_users").select("role,is_active").eq("id", callerId).maybeSingle();

    if (staffError) return json({ error: "Unable to verify staff permissions" }, 500);
    if (!staff || staff.is_active !== true || staff.role !== "super_admin") {
      return json({ error: "Only an active Super Admin can invite teachers" }, 403);
    }

    const body = await req.json().catch(() => null);
    const email = typeof body?.email === "string" ? body.email.trim().toLowerCase() : "";
    const displayName = typeof body?.display_name === "string" ? body.display_name.trim() : "";

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) {
      return json({ error: "A valid email address is required" }, 400);
    }
    if (displayName.length > 100) return json({ error: "Name must be 100 characters or fewer" }, 400);

    const { data: existing } = await ctx.supabaseAdmin.from("admin_users")
      .select("id").ilike("email", email).maybeSingle();
    if (existing) return json({ error: "This email already has a staff account" }, 409);

    const { data: invited, error: inviteError } = await ctx.supabaseAdmin.auth.admin
      .inviteUserByEmail(email, { data: displayName ? { display_name: displayName } : {} });

    if (inviteError || !invited.user) {
      return json({ error: inviteError?.message ?? "Invitation could not be created" }, 400);
    }

    const { error: insertError } = await ctx.supabaseAdmin.from("admin_users").insert({
      id: invited.user.id, email, role: "teacher", is_active: true,
    });

    if (insertError) {
      await ctx.supabaseAdmin.auth.admin.deleteUser(invited.user.id);
      return json({ error: "Teacher invitation could not be finalized" }, 500);
    }
    return json({ ok: true, email, role: "teacher" }, 201);
  } catch (_error) {
    return json({ error: "Unexpected invitation error" }, 500);
  }
});

Deno.serve((req) => req.method === "OPTIONS"
  ? new Response("ok", { headers: corsHeaders })
  : handler(req));
