import { createClient } from 'npm:@supabase/supabase-js@2';

Deno.serve(async (request) => {
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const secret = Deno.env.get('STRIPE_WEBHOOK_SECRET');
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!secret || !supabaseUrl || !serviceRoleKey) {
    console.error('Stripe webhook configuration is incomplete');
    return new Response('Webhook is not configured', { status: 500 });
  }

  const body = await request.text();
  const signature = request.headers.get('Stripe-Signature');
  if (!signature || !(await verifyStripeSignature(body, signature, secret))) {
    return new Response('Invalid Stripe signature', { status: 400 });
  }

  let event: StripeEvent;
  try {
    event = JSON.parse(body);
  } catch {
    return new Response('Invalid event body', { status: 400 });
  }

  if (event.type !== 'checkout.session.completed' && event.type !== 'checkout.session.async_payment_succeeded') {
    return new Response('Event ignored', { status: 200 });
  }

  const session = event.data?.object;
  if (!session || session.payment_status !== 'paid') return new Response('Payment not complete', { status: 200 });

  const intentId = session.client_reference_id;
  const paymentLinkId = typeof session.payment_link === 'string' ? session.payment_link : session.payment_link?.id;
  if (!intentId || !paymentLinkId || !session.id) {
    console.error('Paid Checkout Session is missing its purchase reference');
    return new Response('Missing purchase reference', { status: 400 });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
  const { error } = await admin.rpc('complete_pocony_stripe_purchase', {
    p_stripe_event_id: event.id,
    p_checkout_session_id: session.id,
    p_intent_id: intentId,
    p_payment_link_id: paymentLinkId,
  });
  if (error) {
    console.error('Could not apply paid points purchase', error);
    return new Response('Could not apply points', { status: 500 });
  }

  return new Response('ok', { status: 200 });
});

type StripeEvent = {
  id: string;
  type: string;
  data?: { object?: {
    id?: string;
    client_reference_id?: string | null;
    payment_link?: string | { id?: string } | null;
    payment_status?: string;
  } };
};

async function verifyStripeSignature(body: string, header: string, secret: string): Promise<boolean> {
  const parts = header.split(',').map((part) => part.split('=', 2));
  const timestamp = parts.find(([key]) => key === 't')?.[1];
  const signatures = parts.filter(([key]) => key === 'v1').map(([, value]) => value);
  if (!timestamp || signatures.length === 0) return false;

  const timestampNumber = Number(timestamp);
  if (!Number.isFinite(timestampNumber) || Math.abs(Date.now() / 1000 - timestampNumber) > 300) return false;

  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const signedPayload = new TextEncoder().encode(`${timestamp}.${body}`);
  const digest = new Uint8Array(await crypto.subtle.sign('HMAC', key, signedPayload));
  const expected = [...digest].map((byte) => byte.toString(16).padStart(2, '0')).join('');
  return signatures.some((candidate) => constantTimeEqual(candidate, expected));
}

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let i = 0; i < left.length; i++) difference |= left.charCodeAt(i) ^ right.charCodeAt(i);
  return difference === 0;
}
