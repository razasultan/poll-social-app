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
  Fill in $SupabaseAnonKey below with the PROD project's publishable anon key
  (Supabase dashboard -> poll-social-app -> Settings -> API -> Publishable key,
  also documented in Notion). The PROD project may need to be resumed first if
  it shows as paused/inactive.
#>
param(
    [switch]$Release,
    [string]$Device
)

$SupabaseUrl = "https://ioweogjlumrzcbejwbeb.supabase.co"
$SupabaseAnonKey = "YOUR_PROD_ANON_KEY"

if ($SupabaseAnonKey -eq "YOUR_PROD_ANON_KEY") {
    Write-Error "Set `$SupabaseAnonKey in scripts\run_prod.ps1 to the PROD project's publishable anon key before running this."
    exit 1
}

$flutterArgs = @(
    "run",
    "--dart-define=APP_ENV=prod",
    "--dart-define=SUPABASE_URL=$SupabaseUrl",
    "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey"
)

if ($Release) { $flutterArgs += "--release" }
if ($Device) { $flutterArgs += @("-d", $Device) }

& flutter @flutterArgs
