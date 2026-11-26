<#
.SYNOPSIS
    Checks the page with the living eye in two real browsers, without a window.

.DESCRIPTION
    One call, nothing asked in the middle. It never changes the page: it works on copies
    under target/check, which git ignores.
      1. the page's text: it loads the site's stylesheet, and no rule squashes the dark disc;
      2. Edge, without a window, plays a person on a copy of the page: the pointer enters
         the eye, moves over it, goes far to each side, clicks. At each moment the copy
         measures the eye and writes what it found; this script reads it back;
      3. Firefox and Edge each take a picture of the eye held in the middle of a wink, and
         three points of the picture are read: the dark disc must still be there, round;
      4. the page the site serves is compared with this folder's page, byte for byte
         (line ends aside), so a stale copy online is seen.
    Each line starts with ok, red or skip. Exit code 0 = no red line.

.PARAMETER Page
    The page to check, from the repository's root. dev/index.html by default.

.PARAMETER Url
    Where the site serves that page. https://lorisse.ai/dev/ by default.

.PARAMETER NoServed
    Leave the served page aside (no network at all).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check_page.ps1

.NOTES
    Plain ASCII, Windows PowerShell 5.1 compatible. Downloads nothing but the one page named.
#>
[CmdletBinding()]
param(
    [string]$Page = 'dev/index.html',
    [string]$Url = 'https://lorisse.ai/dev/',
    [switch]$NoServed
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pagePath = Join-Path $root $Page
$out = Join-Path $root 'target/check'
$utf8 = New-Object System.Text.UTF8Encoding $false
$script:red = 0

function Say-Line([string]$verdict, [string]$name, [string]$detail) {
    if ($verdict -eq 'red') { $script:red++ }
    $text = $verdict.PadRight(5) + $name
    if ($detail) { $text = $text + ': ' + $detail }
    Write-Host $text
}

function Find-Program([string[]]$places) {
    foreach ($p in $places) { if (Test-Path -LiteralPath $p) { return $p } }
    return $null
}

function Run-Browser([string]$program, [string[]]$arguments, [string]$stdout) {
    $err = $stdout + '.err'
    $p = Start-Process -FilePath $program -ArgumentList $arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $err
    return $p.ExitCode
}

if (-not (Test-Path -LiteralPath $pagePath)) { Write-Host ('no page at ' + $Page); exit 1 }
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out | Out-Null

$html = [System.IO.File]::ReadAllText($pagePath, [System.Text.Encoding]::UTF8)
$pageDirUri = ([Uri]((Split-Path -Parent $pagePath) + [System.IO.Path]::DirectorySeparatorChar)).AbsoluteUri

# -- 1. the page's text ------------------------------------------------------------------------
$link = [regex]::Match($html, '<link rel="stylesheet" href="([^"]+)"')
if ($link.Success -and (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $pagePath) $link.Groups[1].Value))) {
    Say-Line 'ok' 'the stylesheet the page names is there' ''
} else {
    Say-Line 'red' 'the stylesheet the page names is there' 'not found from the page'
}
$squash = [regex]::Match($html, 'cb-eye-core[^{}]*\{[^}]*(transform|scale)\s*:')
if ($squash.Success) { Say-Line 'red' 'no rule of the page squashes the dark disc' $squash.Value }
else { Say-Line 'ok' 'no rule of the page squashes the dark disc' '' }
foreach ($id in 'eye', 'stage', 'say') {
    if ($html -notmatch ('id="' + $id + '"')) { Say-Line 'red' ('the page holds #' + $id) 'missing' }
}

# -- the copies --------------------------------------------------------------------------------
function Write-Copy([string]$name, [string]$headExtra, [string]$bodyExtra) {
    $copy = $html -replace '<head>', ('<head><base href="' + $pageDirUri + '">' + $headExtra)
    $copy = $copy -replace '</body>', ($bodyExtra + '</body>')
    $path = Join-Path $out $name
    [System.IO.File]::WriteAllText($path, $copy, $utf8)
    return $path
}

$probe = @'
<script>
(function () {
  var R = { errors: [], checks: [] };
  window.addEventListener("error", function (e) { R.errors.push(String(e.message)); });
  var eye = document.getElementById("eye"), stage = document.getElementById("stage"), say = document.getElementById("say");
  if (!eye || !stage || !say) { R.errors.push("the eye, its stage or its line is missing"); return done(); }
  var core = eye.querySelector(".cb-eye-core"), pupil = eye.querySelector(".cb-eye-pupil");
  var quarters = Array.prototype.slice.call(eye.querySelectorAll(".cb-eye-q"));
  function rect(el) { var r = el.getBoundingClientRect(); return { w: r.width, h: r.height, x: r.left + r.width / 2, y: r.top + r.height / 2 }; }
  function check(name, ok, detail) { R.checks.push({ name: name, ok: !!ok, detail: String(detail) }); }
  function disc() { var c = rect(core), e = rect(eye); return { ok: Math.abs(c.w - c.h) < 1.5 && c.w > e.w * 0.7, said: "the dark disc is " + c.w.toFixed(0) + " by " + c.h.toFixed(0) + " in an eye of " + e.w.toFixed(0) }; }
  function round(name) { var d = disc(); check(name, d.ok, d.said); }
  function open(name) { var p = rect(pupil); check(name, Math.abs(p.w - p.h) < 2 && !eye.classList.contains("is-wink"), "the pupil is " + p.w.toFixed(0) + " by " + p.h.toFixed(0)); }
  function move(x, y) { window.dispatchEvent(new PointerEvent("pointermove", { clientX: x, clientY: y, bubbles: true })); }
  function done() { var pre = document.createElement("pre"); pre.id = "check-result"; pre.textContent = JSON.stringify(R); document.body.appendChild(pre); }
  function at(ms, fn) { setTimeout(function () { try { fn(); } catch (e) { R.errors.push(String(e)); } }, ms); }

  at(350, function () { check("it says a word by itself", say.textContent.indexOf("plop") === 0, "it says: " + say.textContent); });
  at(400, function () { round("at rest, the dark disc is round"); open("at rest, the pupil is round"); });
  at(500, function () { eye.dispatchEvent(new MouseEvent("mouseenter")); });
  at(700, function () {
    round("in a wink, the dark disc stays round");
    var p = rect(pupil);
    check("in a wink, the pupil closes", p.h < p.w * 0.3, "the pupil is " + p.w.toFixed(0) + " by " + p.h.toFixed(0));
  });
  at(1300, function () { open("after a wink, the pupil is open again"); });

  // the pointer wanders over the eye for a second, entering it now and then
  var bad = "", worst = 0, n = 0;
  for (var i = 0; i < 20; i++) {
    (function (i) {
      at(1400 + i * 50, function () {
        var e = rect(eye), a = i * 0.9;
        move(e.x + Math.cos(a) * e.w * 0.3, e.y + Math.sin(a) * e.w * 0.3);
        if (i % 5 === 0) eye.dispatchEvent(new MouseEvent("mouseenter"));
        var d = disc(); n++;
        if (!d.ok) bad = d.said;
        var c = rect(core), p = rect(pupil), far = Math.hypot(p.x - c.x, p.y - c.y) + p.w / 2 - c.w / 2;
        if (far > worst) worst = far;
      });
    })(i);
  }
  at(2500, function () {
    check("with the pointer on the eye, the dark disc stays round", !bad, bad || (n + " moments measured"));
    check("the pupil never leaves the dark disc", worst <= 1, "it passes the edge by " + worst.toFixed(1) + " px at most");
  });
  at(3100, function () { open("with the pointer still on the eye, the pupil is open"); });

  at(3200, function () { var e = rect(eye); move(e.x + 600, e.y); });
  at(3500, function () { var c = rect(core), p = rect(pupil); check("the pointer far right, it looks right", p.x - c.x > 4, "the pupil is " + (p.x - c.x).toFixed(1) + " px from the middle"); });
  at(3550, function () { var e = rect(eye); move(e.x - 600, e.y); });
  at(3850, function () { var c = rect(core), p = rect(pupil); check("the pointer far left, it looks left", p.x - c.x < -4, "the pupil is " + (p.x - c.x).toFixed(1) + " px from the middle"); });
  at(3900, function () { var e = rect(eye); move(e.x, e.y + 600); });
  at(4200, function () { var c = rect(core), p = rect(pupil); check("the pointer far below, it looks down", p.y - c.y > 4, "the pupil is " + (p.y - c.y).toFixed(1) + " px from the middle"); });

  at(5200, function () { stage.click(); });
  at(5400, function () { round("in a click, the dark disc stays round"); });
  at(6400, function () {
    check("a click gets an answer underneath", say.textContent === "oui ?", "it says: " + say.textContent);
    var colors = quarters.map(function (q) { var s = getComputedStyle(q); return s.backgroundColor + " " + s.opacity; });
    var same = colors.every(function (c) { return c === colors[0]; });
    check("a click lights the four quarters alike", same && colors.length === 4, colors.join(" | "));
    open("after a click, the pupil is open");
  });
  at(15200, function () {
    check("after a click, its own story comes back", say.textContent.length > 0 && say.textContent !== "oui ?", "it says: " + say.textContent);
    round("at the end, the dark disc is round");
    done();
  });
})();
</script>
'@

$held = @'
<style>
  #eye { position: fixed !important; left: 40px !important; top: 40px !important; width: 220px !important; height: 220px !important; z-index: 9999; }
  #eye .cb-eye-pupil, #eye .cb-eye-core { transition: none !important; animation: none !important; }
  #eye .cb-eye-q { background: var(--cb-blue) !important; opacity: 1 !important; animation: none !important; filter: none !important; }
</style>
'@
$hold = '<script>document.getElementById("eye").classList.add("is-wink");</script>'

# Without a window the browser's clock for a glide between two states does not run, so the copy
# Edge plays on has the glides off: each state is measured as it ends. The pictures of part 3
# show what a wink looks like on the way.
$still = '<style>#eye, #eye * { transition: none !important; }</style>'
$probePath = Write-Copy 'probe.html' $still $probe
$heldPath = Write-Copy 'held.html' $held $hold

$edge = Find-Program @('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', 'C:/Program Files/Microsoft/Edge/Application/msedge.exe')
$firefox = Find-Program @('C:/Program Files/Mozilla Firefox/firefox.exe', 'C:/Program Files (x86)/Mozilla Firefox/firefox.exe')

# -- 2. Edge plays a person --------------------------------------------------------------------
if (-not $edge) {
    Say-Line 'skip' 'Edge plays a person on the page' 'Edge is not on this machine'
} else {
    $dom = Join-Path $out 'probe.dom.txt'
    $browserData = Join-Path $out 'edge-profile'
    $arguments = @('--headless', '--disable-gpu', '--no-first-run', ('--user-data-dir="' + $browserData + '"'), '--window-size=1100,800', '--virtual-time-budget=20000', '--dump-dom', ('"' + ([Uri]$probePath).AbsoluteUri + '"'))
    Run-Browser $edge $arguments $dom | Out-Null
    $text = ''
    if (Test-Path -LiteralPath $dom) { $text = [System.IO.File]::ReadAllText($dom, [System.Text.Encoding]::UTF8) }
    $found = [regex]::Match($text, '(?s)<pre id="check-result">(.*?)</pre>')
    if (-not $found.Success) {
        Say-Line 'red' 'Edge plays a person on the page' 'the copy wrote no result: the page did not run to its end'
    } else {
        $result = [System.Net.WebUtility]::HtmlDecode($found.Groups[1].Value) | ConvertFrom-Json
        foreach ($e in @($result.errors)) { Say-Line 'red' 'the page runs without an error' $e }
        if (@($result.errors).Count -eq 0) { Say-Line 'ok' 'the page runs without an error' '' }
        foreach ($c in @($result.checks)) {
            if ($c.ok) { Say-Line 'ok' $c.name '' } else { Say-Line 'red' $c.name $c.detail }
        }
    }
}

# -- 3. a picture of the eye held in a wink, read at three points ---------------------------------
Add-Type -AssemblyName System.Drawing
function Read-Picture([string]$browser, [string]$png) {
    if (-not (Test-Path -LiteralPath $png)) { Say-Line 'red' ($browser + ': the eye held in a wink') 'no picture was taken'; return }
    $bmp = New-Object System.Drawing.Bitmap $png
    try {
        $k = $bmp.Width / 500.0
        $disc = $bmp.GetPixel([int](150 * $k), [int](95 * $k))
        $ring = $bmp.GetPixel([int](150 * $k), [int](47 * $k))
        $pupil = $bmp.GetPixel([int](150 * $k), [int](150 * $k))
    } finally { $bmp.Dispose() }
    $far = { param($a, $b) [Math]::Abs($a.R - $b.R) + [Math]::Abs($a.G - $b.G) + [Math]::Abs($a.B - $b.B) }
    $said = 'disc ' + $disc.R + ',' + $disc.G + ',' + $disc.B + ' ring ' + $ring.R + ',' + $ring.G + ',' + $ring.B + ' pupil ' + $pupil.R + ',' + $pupil.G + ',' + $pupil.B
    if ((& $far $disc $ring) -gt 90) { Say-Line 'ok' ($browser + ': in a wink the dark disc is still there, above the pupil') '' }
    else { Say-Line 'red' ($browser + ': in a wink the dark disc is still there, above the pupil') ('the quarters show through where the disc should be: ' + $said) }
    if ((& $far $pupil $disc) -gt 90) { Say-Line 'ok' ($browser + ': in a wink the pupil is a line across the middle') '' }
    else { Say-Line 'red' ($browser + ': in a wink the pupil is a line across the middle') $said }
}

$heldUri = ([Uri]$heldPath).AbsoluteUri
if ($edge) {
    $png = Join-Path $out 'held-edge.png'
    $browserData = Join-Path $out 'edge-profile'
    Run-Browser $edge @('--headless', '--disable-gpu', '--no-first-run', '--hide-scrollbars', ('--user-data-dir="' + $browserData + '"'), '--window-size=500,400', ('--screenshot="' + $png + '"'), ('"' + $heldUri + '"')) (Join-Path $out 'held-edge.out.txt') | Out-Null
    Read-Picture 'Edge' $png
}
if (-not $firefox) {
    Say-Line 'skip' 'Firefox: the eye held in a wink' 'Firefox is not on this machine'
} else {
    $png = Join-Path $out 'held-firefox.png'
    $browserData = Join-Path $out 'firefox-profile'
    New-Item -ItemType Directory -Force -Path $browserData | Out-Null
    Run-Browser $firefox @('--headless', '--no-remote', '--profile', ('"' + $browserData + '"'), '--window-size=500,400', '--screenshot', ('"' + $png + '"'), ('"' + $heldUri + '"')) (Join-Path $out 'held-firefox.out.txt') | Out-Null
    Read-Picture 'Firefox' $png
}

# -- 4. the page the site serves -----------------------------------------------------------------
function Get-Mark([byte[]]$bytes) {
    $kept = New-Object System.Collections.Generic.List[byte]
    foreach ($b in $bytes) { if ($b -ne 13) { $kept.Add($b) } }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($kept.ToArray())) } finally { $sha.Dispose() }
}
if ($NoServed) {
    Say-Line 'skip' 'the page online is this folder''s page' 'left aside'
} else {
    try {
        $client = New-Object System.Net.WebClient
        $served = $client.DownloadData($Url + '?check=' + [DateTime]::UtcNow.Ticks)
        $client.Dispose()
        if ((Get-Mark $served) -eq (Get-Mark ([System.IO.File]::ReadAllBytes($pagePath)))) {
            Say-Line 'ok' 'the page online is this folder''s page' ''
        } else {
            Say-Line 'red' 'the page online is this folder''s page' ('what ' + $Url + ' serves differs: the site has not taken the last push yet, or the push is missing')
        }
    } catch {
        Say-Line 'red' 'the page online is this folder''s page' ('could not be read: ' + $_.Exception.Message)
    }
}

if ($script:red -gt 0) { Write-Host ('red: ' + $script:red + ' line(s)'); exit 1 }
Write-Host 'green'
exit 0
