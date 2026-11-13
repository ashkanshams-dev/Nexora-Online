// Public Supabase client config (same as src/net/publicConfig.ts). Safe to ship: the anon key only grants
// what Row Level Security allows. Overridable at build time with --dart-define.
const PUBLIC_SUPABASE_URL = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://eisstodgncimypdawisy.supabase.co');
const PUBLIC_SUPABASE_ANON_KEY = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVpc3N0b2RnbmNpbXlwZGF3aXN5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQyMjkwMTAsImV4cCI6MjEwOTgwNTAxMH0.uEPldAQjJdRyZTGXaz_OpFR7WpFXMiPXlW1S34cR3p8');
