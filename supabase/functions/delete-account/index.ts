import { createClient } from "npm:@supabase/supabase-js@2";

type ErrorResponse = {
  error: string;
};

const jsonHeaders = {
  "Content-Type": "application/json",
};

Deno.serve(async (request) => {
  if (request.method !== "DELETE" && request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = request.headers.get("Authorization");

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ error: "Server is missing Supabase configuration." }, 500);
  }

  if (!authorization) {
    return json({ error: "Missing authorization header." }, 401);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: {
      headers: {
        Authorization: authorization,
      },
    },
  });

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return json({ error: "Unable to verify the current user." }, 401);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });

  const { error: deleteError } = await adminClient.auth.admin.deleteUser(
    userData.user.id,
    false,
  );
  if (deleteError) {
    return json({ error: deleteError.message }, 500);
  }

  return new Response(null, {
    status: 204,
    headers: jsonHeaders,
  });
});

function json(body: ErrorResponse, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  });
}
