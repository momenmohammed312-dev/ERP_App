-- Create Licenses Table
CREATE TABLE public.licenses (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    license_key TEXT UNIQUE NOT NULL,
    customer_name TEXT,
    phone TEXT,
    plan TEXT NOT NULL DEFAULT 'standard',
    features JSONB NOT NULL DEFAULT '[]'::jsonb,
    max_devices INT NOT NULL DEFAULT 1,
    max_transfers INT NOT NULL DEFAULT 1,
    expires_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'active', -- active, suspended, revoked
    source TEXT DEFAULT 'new', -- new, legacy
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create Devices Table
CREATE TABLE public.devices (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    license_id UUID NOT NULL REFERENCES public.licenses(id) ON DELETE CASCADE,
    machine_guid TEXT,
    install_uuid TEXT,
    device_name TEXT,
    platform TEXT,
    app_version TEXT,
    first_seen TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT now(),
    status TEXT NOT NULL DEFAULT 'active', -- active, removed
    UNIQUE(license_id, machine_guid),
    UNIQUE(license_id, install_uuid)
);

-- Create Events Table
CREATE TABLE public.license_events (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    license_id UUID REFERENCES public.licenses(id) ON DELETE CASCADE,
    device_id UUID REFERENCES public.devices(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL, -- activate, checkin, reject, transfer, suspended
    payload JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS (Block all public access from the app, only allow Edge Functions with service_role)
ALTER TABLE public.licenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.license_events ENABLE ROW LEVEL SECURITY;
