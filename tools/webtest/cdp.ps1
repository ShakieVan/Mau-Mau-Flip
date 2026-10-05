# Mau-Mau Flip – Prüfhilfe für den Browser-Client: Chrome headless über das DevTools-Protokoll steuern.
# Grund: Mit --headless=new und --window-size stimmt das Layout-Fenster nicht mit dem Bild überein (Rahmenabzug,
# Mindestbreite ~500 px). Über Emulation.setDeviceMetricsOverride entstehen exakte Handy-Ansichten (Größe, Dichte, Touch).
#
# Beispiel:
#   powershell -NoProfile -File tools\webtest\cdp.ps1 -Url "file:///E:/.../index.html?mock=1" -Out shot.png -Width 844 -Height 390 -Scale 2 -Mobile
param(
	[Parameter(Mandatory = $true)][string]$Url,
	[string]$Out = '',
	[int]$Width = 844,
	[int]$Height = 390,
	[double]$Scale = 2,
	[switch]$Mobile,
	[string]$UserAgent = '',
	[string]$WaitExpr = 'true',
	[int]$WaitMs = 1200,
	[int]$TimeoutMs = 20000,
	[string]$Eval = '',
	[string]$Pre = '',
	[switch]$Console
)
$ErrorActionPreference = 'Stop'
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$port = Get-Random -Minimum 9400 -Maximum 9900
$prof = Join-Path $env:TEMP ('mmf-cdp-' + $port)
$argList = @('--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check', '--disable-extensions', '--hide-scrollbars',
	'--mute-audio', '--autoplay-policy=no-user-gesture-required', "--remote-debugging-port=$port", "--user-data-dir=`"$prof`"", '--window-size=1920,1080', 'about:blank')
$proc = Start-Process -FilePath $chrome -ArgumentList $argList -PassThru -WindowStyle Hidden
$client = $null
$script:nr = 0
$script:fehler = 0

function Lies-Nachricht {
	$buf = New-Object byte[] 262144
	$ms = New-Object IO.MemoryStream
	do {
		$seg = New-Object 'ArraySegment[byte]' -ArgumentList (, $buf)
		$r = $client.ReceiveAsync($seg, [Threading.CancellationToken]::None).Result
		$ms.Write($buf, 0, $r.Count)
	} while (-not $r.EndOfMessage)
	return [Text.Encoding]::UTF8.GetString($ms.ToArray())
}
function Sende([string]$methode, $parameter) {
	$script:nr++
	$id = $script:nr
	$msg = @{ id = $id; method = $methode; params = $parameter } | ConvertTo-Json -Depth 10 -Compress
	$bytes = [Text.Encoding]::UTF8.GetBytes($msg)
	$seg = New-Object 'ArraySegment[byte]' -ArgumentList (, $bytes)
	$client.SendAsync($seg, [Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).Wait()
	while ($true) {
		$t = Lies-Nachricht
		if ($t.StartsWith('{"id":' + $id + ',')) { return $t }
		if ($t -match '"method":"Runtime.exceptionThrown"') { $script:fehler++; if ($Console) { Write-Host ('EXCEPTION: ' + $t.Substring(0, [Math]::Min(600, $t.Length))) } }
		elseif ($Console -and $t -match '"method":"Runtime.consoleAPICalled"') {
			$m = [regex]::Match($t, '"value":"((?:[^"\\]|\\.)*)"')
			if ($m.Success) { Write-Host ('CONSOLE: ' + $m.Groups[1].Value) }
		}
	}
}
function Werte([string]$ausdruck) {
	$a = Sende 'Runtime.evaluate' @{ expression = $ausdruck; returnByValue = $true; awaitPromise = $true }
	$o = $a | ConvertFrom-Json
	if ($o.result.exceptionDetails) { return $null }
	return $o.result.result.value
}

try {
	$ws = $null
	for ($i = 0; $i -lt 150 -and -not $ws; $i++) {
		try {
			$liste = Invoke-RestMethod -Uri "http://127.0.0.1:$port/json/list" -TimeoutSec 1
			$seite = $liste | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
			if ($seite) { $ws = $seite.webSocketDebuggerUrl }
		} catch { }
		if (-not $ws) { Start-Sleep -Milliseconds 100 }
	}
	if (-not $ws) { throw 'DevTools-Endpunkt nicht erreichbar' }
	$client = New-Object System.Net.WebSockets.ClientWebSocket
	$client.ConnectAsync([Uri]$ws, [Threading.CancellationToken]::None).Wait()
	$null = Sende 'Page.enable' @{}
	$null = Sende 'Runtime.enable' @{}
	$ausrichtung = if ($Width -ge $Height) { @{ type = 'landscapePrimary'; angle = 90 } } else { @{ type = 'portraitPrimary'; angle = 0 } }
	$null = Sende 'Emulation.setDeviceMetricsOverride' @{ width = $Width; height = $Height; deviceScaleFactor = $Scale; mobile = [bool]$Mobile; screenOrientation = $ausrichtung }
	if ($Mobile) { $null = Sende 'Emulation.setTouchEmulationEnabled' @{ enabled = $true; maxTouchPoints = 5 } }
	if ($UserAgent) { $null = Sende 'Emulation.setUserAgentOverride' @{ userAgent = $UserAgent } }
	$null = Sende 'Page.navigate' @{ url = $Url }
	$ende = (Get-Date).AddMilliseconds($TimeoutMs)
	$bereit = $false
	Start-Sleep -Milliseconds 200
	while ((Get-Date) -lt $ende) {
		$v = Werte $WaitExpr
		if ($v) { $bereit = $true; break }
		Start-Sleep -Milliseconds 200
	}
	if (-not $bereit) { Write-Output "WARTEN: Zeitueberschreitung ($WaitExpr)" }
	if ($Pre) { $null = Werte $Pre; Start-Sleep -Milliseconds 150 }
	Start-Sleep -Milliseconds $WaitMs
	if ($Out) {
		$a = Sende 'Page.captureScreenshot' @{ format = 'png' }
		$m = [regex]::Match($a, '"data":"([^"]+)"')
		if (-not $m.Success) { throw 'Kein Bild erhalten' }
		[IO.File]::WriteAllBytes($Out, [Convert]::FromBase64String($m.Groups[1].Value))
		Write-Output "BILD: $Out"
	}
	if ($Eval) { $e = Werte $Eval; Write-Output ('EVAL: ' + $e) }
	if ($script:fehler) { Write-Output "JS-AUSNAHMEN: $script:fehler" }
	try { $null = Sende 'Browser.close' @{} } catch { }
} finally {
	if ($client) { try { $client.Dispose() } catch { } }
	Start-Sleep -Milliseconds 300
	if (-not $proc.HasExited) { try { Stop-Process -Id $proc.Id -Force } catch { } }
	Start-Sleep -Milliseconds 300
	try { Remove-Item -Recurse -Force $prof -ErrorAction SilentlyContinue } catch { }
}
