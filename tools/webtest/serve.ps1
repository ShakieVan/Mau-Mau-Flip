# Mau-Mau Flip – kleiner statischer HTTP-Server für Prüfungen des Browser-Clients über http:// (statt file://).
# Liefert webclient/ unter http://localhost:<Port>/ aus, mit den MIME-Typen, die auch der Gastgeber senden muss.
# /info antwortet mit Beispieldaten, /ws gibt 404 (kein Spiel; für den Spielablauf ?mock=1 verwenden).
# Aufruf: powershell -NoProfile -File tools\webtest\serve.ps1 [-Port 8123] [-Sekunden 120]
param([int]$Port = 8123, [int]$Sekunden = 120)
$ErrorActionPreference = 'Stop'
$wurzel = (Resolve-Path (Join-Path $PSScriptRoot '..\..\webclient')).Path
$typen = @{
	'.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'
	'.json' = 'application/json'; '.webp' = 'image/webp'; '.png' = 'image/png'; '.svg' = 'image/svg+xml'
	'.woff2' = 'font/woff2'; '.ttf' = 'font/ttf'; '.mp4' = 'video/mp4'; '.m4a' = 'audio/mp4'; '.ogg' = 'audio/ogg'; '.txt' = 'text/plain; charset=utf-8'
}
$h = New-Object System.Net.HttpListener
$h.Prefixes.Add("http://localhost:$Port/")
$h.Start()
Write-Output "Server: http://localhost:$Port/ ($wurzel)"
$ende = (Get-Date).AddSeconds($Sekunden)
try {
	while ((Get-Date) -lt $ende) {
		$aufgabe = $h.GetContextAsync()
		while (-not $aufgabe.Wait(250)) { if ((Get-Date) -ge $ende) { break } }
		if (-not $aufgabe.IsCompleted) { break }
		$k = $aufgabe.Result
		$pfad = [Uri]::UnescapeDataString($k.Request.Url.AbsolutePath)
		$antwort = $k.Response
		try {
			if ($pfad -eq '/info') {
				$b = [Text.Encoding]::UTF8.GetBytes('{"game":"mau-mau-flip","version":"0.1.1","name":"Testserver","players":2,"port":' + $Port + '}')
				$antwort.ContentType = 'application/json'
			} else {
				if ($pfad -eq '/') { $pfad = '/index.html' }
				$datei = Join-Path $wurzel ($pfad.TrimStart('/') -replace '/', '\')
				$voll = [IO.Path]::GetFullPath($datei)
				if (-not $voll.StartsWith($wurzel) -or -not (Test-Path -LiteralPath $voll -PathType Leaf)) { $antwort.StatusCode = 404; $b = [Text.Encoding]::UTF8.GetBytes('nicht gefunden') }
				else {
					$b = [IO.File]::ReadAllBytes($voll)
					$t = $typen[[IO.Path]::GetExtension($voll).ToLower()]
					$antwort.ContentType = if ($t) { $t } else { 'application/octet-stream' }
				}
			}
			Write-Output ("{0} {1} {2}" -f $antwort.StatusCode, $k.Request.HttpMethod, $pfad)
			$antwort.ContentLength64 = $b.Length
			$antwort.OutputStream.Write($b, 0, $b.Length)
		} catch { } finally { try { $antwort.Close() } catch { } }
	}
} finally { $h.Stop(); $h.Close() }
