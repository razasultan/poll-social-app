<#
.SYNOPSIS
  Runs the Flutter app against the PROD Supabase backend (poll-social-app).

.PARAMETER Release
  Run in release mode instead of the default debug mode.

.PARAMETER Device
  Flutter device id to target, e.g. "windows", "chrome" (passed through as -d).

.EXAMPLE
  .\scripts\run_prod.ps1
  .\scripts\run_prod.ps1 -Release -Device windows

.NOTES
  Targets the PROD Supabase project (poll-social-app). Get a fresh publishable
  key from the Supabase dashboard (Settings -> API -> Publishable key) if it
  ever rotates.
#>
param(
    [switch]$Release,
    [string]$Device
)

$SupabaseUrl = "https://ioweogjlumrzcbejwbeb.supabase.co"
$SupabaseAnonKey = "sb_publishable_eBRj_ukaVQGpeAfcjwKvjQ_8sIu7PIP"

$flutterArgs = @(
    "run",
    "--dart-define=APP_ENV=prod",
    "--dart-define=SUPABASE_URL=$SupabaseUrl",
    "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey"
)

if ($Release) { $flutterArgs += "--release" }
if ($Device) { $flutterArgs += @("-d", $Device) }

& flutter @flutterArgs
