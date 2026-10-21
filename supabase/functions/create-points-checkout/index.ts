import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const packs = {
  basic: {
    points: 115,
    url: 'https://buy.stripe.com/eVqeVd5kGfOD7wnfAl1wY00',
    paymentLinkId: 'plink_1USra5Daj1MxRXJto4QgtTS0',
  },
  value: {
    points: 365,
    url: 'https://buy.stripe.com/28EdR98wSeKz6sjdsd1wY01',
    paymentLinkId: 'plink_1USrciDaj1MxRXJtBZFpKZBL',
  },
} as const;

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const authorization = request.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) return json({ error: 'Unauthorized' }, 401);

  try {
    const { pack } = await request.json();
    if (pack !== 'basic' && pack !== 'value') return json({ error: 'Unknown pack' }, 400);

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !anonKey || !serviceRoleKey) throw new Error('Supabase function configuration is incomplete');

    const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authorization } } });
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) return json({ error: 'Unauthorized' }, 401);

    const selectedPack = packs[pack];
    const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
    const { data: intent, error: insertError } = await admin
      .from('pocony_stripe_purchase_intents')
      .insert({ uid: user.id, payment_link_id: selectedPack.paymentLinkId, points: selectedPack.points })
      .select('id')
      .single();
    if (insertError || !intent) throw insertError ?? new Error('Could not create purchase intent');

    const checkoutUrl = new URL(selectedPack.url);
    checkoutUrl.searchParams.set('client_reference_id', intent.id);
    return json({ url: checkoutUrl.toString() }, 200);
  } catch (error) {
    console.error('Could not create points checkout', error);
    return json({ error: 'Could not start checkout' }, 500);
  }
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
