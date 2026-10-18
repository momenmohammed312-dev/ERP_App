import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { SignJWT, importPKCS8 } from "https://esm.sh/jose@5.2.0";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    
    // We use the service role key to bypass RLS, because the app itself has NO access to the tables.
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const body = await req.json();
    const { action, license_key, machine_guid, install_uuid, device_name, platform, app_version } = body;

    if (!license_key) {
      return new Response(JSON.stringify({ error: 'License key is required' }), { status: 400, headers: corsHeaders });
    }

    // 1. Find the license
    const { data: license, error: licenseError } = await supabase
      .from('licenses')
      .select('*')
      .eq('license_key', license_key)
      .single();

    if (licenseError || !license) {
      return new Response(JSON.stringify({ error: 'Invalid license key' }), { status: 404, headers: corsHeaders });
    }

    if (license.status !== 'active') {
      await logEvent(supabase, license.id, null, 'reject', { reason: `license_${license.status}` });
      return new Response(JSON.stringify({ error: `License is ${license.status}` }), { status: 403, headers: corsHeaders });
    }

    if (license.expires_at && new Date(license.expires_at) < new Date()) {
      await logEvent(supabase, license.id, null, 'reject', { reason: 'license_expired' });
      return new Response(JSON.stringify({ error: 'License expired' }), { status: 403, headers: corsHeaders });
    }

    // 2. Device matching logic
    // We try to find the device by machine_guid OR install_uuid
    const { data: devices, error: devicesError } = await supabase
      .from('devices')
      .select('*')
      .eq('license_id', license.id);

    let currentDevice = devices?.find(d => 
      (!!machine_guid && d.machine_guid === machine_guid) || (!!install_uuid && d.install_uuid === install_uuid)
    );

    if (!currentDevice) {
      // New device - check if we have room
      const activeDevices = devices?.filter(d => d.status === 'active') || [];
      
      if (activeDevices.length >= license.max_devices) {
        // Device limit reached
        await logEvent(supabase, license.id, null, 'reject', { reason: 'device_limit_reached', machine_guid });
        return new Response(JSON.stringify({ error: 'Device limit reached for this license. Contact support to transfer.' }), { status: 403, headers: corsHeaders });
      }

      // Register new device
      const { data: newDev, error: newDevError } = await supabase
        .from('devices')
        .insert({
          license_id: license.id,
          machine_guid,
          install_uuid,
          device_name,
          platform,
          app_version
        })
        .select()
        .single();
        
      if (newDevError) throw newDevError;
      currentDevice = newDev;
      await logEvent(supabase, license.id, currentDevice.id, 'activate', { device_name });
    } else {
      // Update last seen and sync any changed IDs (e.g. if machine_guid changed but install_uuid matched)
      await supabase
        .from('devices')
        .update({ 
          last_seen: new Date().toISOString(),
          machine_guid,
          install_uuid,
          device_name,
          app_version
        })
        .eq('id', currentDevice.id);
        
      await logEvent(supabase, license.id, currentDevice.id, 'checkin', {});
    }

    if (currentDevice.status !== 'active') {
      return new Response(JSON.stringify({ error: 'Device blocked' }), { status: 403, headers: corsHeaders });
    }

    // 3. Generate Signed JWT Lease
    const privateKeyPem = Deno.env.get('LICENSE_PRIVATE_KEY');
    if (!privateKeyPem) {
      throw new Error('LICENSE_PRIVATE_KEY is not configured on the server');
    }

    // Secrets often lose real newlines when pasted; restore them.
    const privateKey = await importPKCS8(privateKeyPem.replace(/\\n/g, '\n'), 'RS256');
    
    // Lease is valid for 30 days, or until license expires (whichever is sooner)
    const thirtyDaysFromNow = new Date();
    thirtyDaysFromNow.setDate(thirtyDaysFromNow.getDate() + 30);
    
    let leaseExpiry = thirtyDaysFromNow;
    if (license.expires_at) {
      const licenseExpiryDate = new Date(license.expires_at);
      if (licenseExpiryDate < thirtyDaysFromNow) {
        leaseExpiry = licenseExpiryDate;
      }
    }

    const jwt = await new SignJWT({
      license_key: license.license_key,
      machine_guid,
      install_uuid,
      plan: license.plan,
      features: license.features,
      license_expires_at: license.expires_at,
      status: 'active'
    })
      .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
      .setIssuedAt()
      .setExpirationTime(Math.floor(leaseExpiry.getTime() / 1000))
      .sign(privateKey);

    return new Response(
      JSON.stringify({
        status: 'success',
        lease_token: jwt,
        expires_at: leaseExpiry.toISOString(),
        server_time: new Date().toISOString()
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error: any) {
    console.error(error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: corsHeaders,
    });
  }
});

async function logEvent(supabase: any, license_id: string, device_id: string | null, event_type: string, payload: any) {
  await supabase.from('license_events').insert({
    license_id,
    device_id,
    event_type,
    payload
  });
}
