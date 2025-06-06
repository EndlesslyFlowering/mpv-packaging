$fallback7z = Join-Path (Get-Location) "\7z\7zr.exe";
$useragent = "mpv-win-updater"

function Wrong-Arch($exe) {
    $fail_string = @"
It seems like $exe could not be run... Are you on the wrong arch?
If so:
- download the 7zip archive matching your CPU arch from 'https://api.github.com/repos/EndlesslyFlowering/mpv-winbuild-cmake/releases/latest'
- extract all the files from the archive into this folder and override all files
- delete the 'settings.xml' file
- rerun the 'updater.bat' file
- choose the correct CPU arch this time
"@
    Write-Host $fail_string -ForegroundColor Red
    cmd /c pause
    throw
}

function Settings-File-Does-Not-Exist {
    throw "'settings.xml' does not exist! Please report this error, Thank You."
}

function Get-7z {
    $7z_command = Get-Command -CommandType Application -ErrorAction Ignore 7z.exe | Select-Object -Last 1
    if ($7z_command) {
        return $7z_command.Source
    }
    $7zdir = Get-ItemPropertyValue -ErrorAction Ignore "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\7-Zip" "InstallLocation"
    if ($7zdir -and (Test-Path (Join-Path $7zdir "7z.exe"))) {
        return Join-Path $7zdir "7z.exe"
    }
    if (Test-Path $fallback7z) {
        return $fallback7z
    }
    return $null
}

function Check-7z {
    if (-not (Get-7z))
    {
        $null = New-Item -ItemType Directory -Force (Split-Path $fallback7z)
        $download_file = $fallback7z
        Write-Host "Downloading 7zr.exe" -ForegroundColor Green
        Invoke-WebRequest -Uri "https://www.7-zip.org/a/7zr.exe" -UserAgent $useragent -OutFile $download_file
    }
    else
    {
        Write-Host "7z already exist. Skipped download" -ForegroundColor Green
    }
}

function Check-PowershellVersion {
    $version = $PSVersionTable.PSVersion.Major
    Write-Host "Checking Windows PowerShell version -- $version" -ForegroundColor Green
    if ($version -le 2)
    {
        Write-Host "Using Windows PowerShell $version is unsupported. Upgrade your Windows PowerShell." -ForegroundColor Red
        throw
    }
}

function Check-Ytplugin {
    $ytdlp = Get-ChildItem "yt-dlp*.exe" -ErrorAction Ignore
    if ($ytdlp) {
        return $ytdlp.ToString()
    }
    else {
        return $null
    }
}

function Check-Ytplugin-In-System {
    $ytp = Get-Command -CommandType Application -ErrorAction Ignore yt-dlp.exe | Select-Object -Last 1
    return [bool]($ytp -and ((Split-Path $ytp.Source) -ne (Get-Location)))
}

function Check-Mpv {
    $mpv = (Get-Location).Path + "\mpv.exe"
    $is_exist = Test-Path $mpv
    return $is_exist
}

function Download-Archive ($filename, $link) {
    Write-Host "Downloading" $filename -ForegroundColor Green
    Invoke-WebRequest -Uri $link -UserAgent $useragent -OutFile $filename
}

function Download-Ytplugin ($version) {
    $plugin = "yt-dlp"
    Write-Host "Downloading $plugin ($version)" -ForegroundColor Green
    if (-Not (Test-Path (Join-Path $env:windir "SysWow64"))) {
        throw "32bit architectures are not supported!"
    }
    $link = -join("https://github.com/yt-dlp/yt-dlp/releases/download/", $version, "/", $plugin, ".exe")
    $plugin_exe = -join($plugin, ".exe")
    Invoke-WebRequest -Uri $link -UserAgent $useragent -OutFile $plugin_exe
}

function Extract-Archive ($file) {
    $7z = Get-7z
    Write-Host "Extracting" $file -ForegroundColor Green
    & $7z x -y $file
}

function Get-Latest-Mpv($Arch) {
    $api_gh = "https://api.github.com/repos/EndlesslyFlowering/mpv-winbuild-cmake/releases/latest"
    $json = Invoke-WebRequest $api_gh -MaximumRedirection 0 -ErrorAction Ignore -UseBasicParsing | ConvertFrom-Json
    $filename = $json.assets | where { $_.name -Match "mpv-$Arch" } | Select-Object -ExpandProperty name
    $download_link = $json.assets | where { $_.name -Match "mpv-$Arch" } | Select-Object -ExpandProperty browser_download_url
    if ($filename -is [array]) {
        return $filename[0], $download_link[0]
    }
    else {
        return $filename, $download_link
    }
}

function Get-Latest-Ytplugin {
    $link = "https://github.com/yt-dlp/yt-dlp/releases.atom"
    Write-Host "Fetching RSS feed for yt-dlp" -ForegroundColor Green
    $resp = [xml](Invoke-WebRequest $link -MaximumRedirection 0 -ErrorAction Ignore -UseBasicParsing).Content
    $link = $resp.feed.entry[0].link.href
    $version = $link.split("/")[-1]
    return $version
}

function Get-Latest-FFmpeg ($Arch) {
    $api_gh = "https://api.github.com/repos/EndlesslyFlowering/mpv-winbuild-cmake/releases/latest"
    $json = Invoke-WebRequest $api_gh -MaximumRedirection 0 -ErrorAction Ignore -UseBasicParsing | ConvertFrom-Json
    $filename = $json.assets | where { $_.name -Match "ffmpeg-$Arch" } | Select-Object -ExpandProperty name
    $download_link = $json.assets | where { $_.name -Match "ffmpeg-$Arch" } | Select-Object -ExpandProperty browser_download_url
    if ($filename -is [array]) {
        return $filename[0], $download_link[0]
    }
    else {
        return $filename, $download_link
    }
}

function ExtractGitFromFile {
    $stripped = .\mpv --no-config | select-string "mpv" | select-object -First 1
    if ($stripped) {
        $pattern = "-g([a-z0-9-]{7})"
        $bool = $stripped -match $pattern
        return $matches[1]
    }
    else {
        Wrong-Arch "mpv"
    }
}

function ExtractGitFromURL($filename) {
    $pattern = "-git-([a-z0-9-]{7})"
    $bool = $filename -match $pattern
    return $matches[1]
}

function ExtractDateFromFile {
    $date = (Get-Item ./mpv.exe).LastWriteTimeUtc
    $day = $date.Day.ToString("00")
    $month = $date.Month.ToString("00")
    $year = $date.Year.ToString("0000")
    return "$year$month$day"
}

function ExtractDateFromURL($filename) {
    $pattern = "mpv-[xi864_].*-([0-9]{8})-git-([a-z0-9-]{7})"
    $bool = $filename -match $pattern
    return $matches[1]
}

function Test-Admin
{
    $user = [Security.Principal.WindowsIdentity]::GetCurrent();
    (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Create-XML {
@"
<settings>
  <arch>unset</arch>
  <autodelete>unset</autodelete>
  <getffmpeg>unset</getffmpeg>
</settings>
"@ | Set-Content "settings.xml" -Encoding UTF8
}

function Check-XmlFileExist {
    $file = "settings.xml"

    if (-not (Test-Path $file)) {
        Create-XML
    }
}

function Check-Arch {
    $get_arch = ""
    $file = "settings.xml"

    if (-not (Test-Path $file)) {
        Settings-File-Does-Not-Exist
    }
    [xml]$doc = Get-Content $file
    if ($doc.settings.arch -eq "unset") {
        $result = Read-KeyOrTimeout "Choose variant for 64bit builds: x86_64-znver3, x86_64-znver4 or x86_64-znver5 [1=x86_64-znver3 / 2=x86_64-znver4 / 3=x86_64-znver5 (default=1)" "D1"
        Write-Host ""
        if ($result -eq 'D1') {
            $get_arch = "x86_64-znver3"
        }
        elseif ($result -eq 'D2') {
            $get_arch = "x86_64-znver4"
        }
        elseif ($result -eq 'D3') {
            $get_arch = "x86_64-znver5"
        }
        else {
            throw "Please enter valid input key."
        }
        $doc.settings.arch = $get_arch
        $doc.Save($file)
    }
    else {
        $get_arch = $doc.settings.arch
    }
    return $get_arch
}

function Check-Autodelete($archive) {
    $autodelete = ""
    $file = "settings.xml"

    if (-not (Test-Path $file)) {
        Settings-File-Does-Not-Exist
    }
    [xml]$doc = Get-Content $file
    if ($doc.settings.autodelete -eq "unset") {
        $result = Read-KeyOrTimeout "Delete archives after extract? [Y/n] (default=Y)" "Y"
        Write-Host ""
        if ($result -eq 'Y') {
            $autodelete = "true"
        }
        elseif ($result -eq 'N') {
            $autodelete = "false"
        }
        else {
            throw "Please enter valid input key."
        }
        $doc.settings.autodelete = $autodelete
        $doc.Save($file)
    }
    if ($doc.settings.autodelete -eq "true") {
        if (Test-Path $archive)
        {
            Remove-Item -Force $archive
        }
    }
}

function Check-GetFFmpeg() {
    $get_ffmpeg = ""
    $file = "settings.xml"

    if (-not (Test-Path $file)) {
        Settings-File-Does-Not-Exist
    }
    [xml]$doc = Get-Content $file
    if ($doc.settings.getffmpeg -eq "unset") {
        Write-Host "FFmpeg doesn't exist. " -ForegroundColor Green -NoNewline
        $result = Read-KeyOrTimeout "Proceed with downloading? [Y/n] (default=n)" "N"
        Write-Host ""
        if ($result -eq 'Y') {
            $get_ffmpeg = "true"
        }
        elseif ($result -eq 'N') {
            $get_ffmpeg = "false"
        }
        else {
            throw "Please enter valid input key."
        }
        $doc.settings.getffmpeg = $get_ffmpeg
        $doc.Save($file)
    }
    else {
        $get_ffmpeg = $doc.settings.getffmpeg
    }
    return $get_ffmpeg
}

function Upgrade-Mpv {
    $need_download = $false
    $remoteName = ""
    $download_link = ""
    $arch = ""

    if (Check-Mpv) {
        Check-XmlFileExist
        $arch = Check-Arch
        $remoteName, $download_link = Get-Latest-Mpv $arch
        $localgit = ExtractGitFromFile
        $localdate = ExtractDateFromFile
        $remotegit = ExtractGitFromURL $remoteName
        $remotedate = ExtractDateFromURL $remoteName
        if ($localgit -match $remotegit)
        {
            if ($localdate -match $remotedate)
            {
                Write-Host "You are already using latest mpv build -- $remoteName" -ForegroundColor Green
                $need_download = $false
            }
            else {
                Write-Host "Newer mpv build available" -ForegroundColor Green
                $need_download = $true
            }
        }
        else {
            Write-Host "Newer mpv build available" -ForegroundColor Green
            $need_download = $true
        }
    }
    else {
        Write-Host "mpv doesn't exist. " -ForegroundColor Green -NoNewline
        $result = Read-KeyOrTimeout "Proceed with downloading? [Y/n] (default=y)" "Y"
        Write-Host ""

        if ($result -eq 'Y') {
            $need_download = $true
            if (Test-Path (Join-Path $env:windir "SysWow64")) {
                Write-Host "Detecting System Type is 64-bit" -ForegroundColor Green
            }
            else {
                throw "32bit architectures are not supported!"
            }
            Check-XmlFileExist
            $arch = Check-Arch
            $remoteName, $download_link = Get-Latest-Mpv $arch
        }
        elseif ($result -eq 'N') {
            $need_download = $false
        }
        else {
            throw "Please enter valid input key."
        }
    }

    if ($need_download) {
        Download-Archive $remoteName $download_link
        Check-7z
        Extract-Archive $remoteName
    }
    Check-Autodelete $remoteName
}

function Upgrade-Ytplugin {
    if (Check-Ytplugin-In-System) {
        Write-Host "yt-dlp.exe already exists in your system, skip the update check." -ForegroundColor Green
        return
    }
    $yt = Check-Ytplugin
    if ($yt) {
        $latest_release = Get-Latest-Ytplugin
        if ((& $yt --version) -match ($latest_release)) {
            Write-Host "You are already using latest" (Get-Item $yt).BaseName "-- $latest_release" -ForegroundColor Green
        }
        else {
            Write-Host "Newer" (Get-Item $yt).BaseName "build available" -ForegroundColor Green
            & $yt --update
        }
    }
    else {
        Write-Host "yt-dlp doesn't exist." -ForegroundColor Green -NoNewline
        $result = Read-KeyOrTimeout "Proceed with downloading? [Y/n] (default=n)" "N"
        Write-Host ""

        if ($result -eq 'Y') {
            $latest_release = Get-Latest-Ytplugin
            Download-Ytplugin $latest_release
        }
    }
}

function Upgrade-FFmpeg {
    $get_ffmpeg = Check-GetFFmpeg
    if ($get_ffmpeg -eq "false") {
        return
    }

    if (Test-Path (Join-Path $env:windir "SysWow64")) {
        $arch = Check-Arch
    }
    else {
        throw "32bit architectures are not supported!"
    }

    $need_download = $false
    $remote_name, $download_link = Get-Latest-FFmpeg $arch
    $ffmpeg = (Get-Location).Path + "\ffmpeg.exe"
    $ffmpeg_exist = Test-Path $ffmpeg

    if ($ffmpeg_exist) {
        $ffmpeg_file = .\ffmpeg -version | select-string "ffmpeg" | select-object -First 1
        if ($ffmpeg_file) {
            $file_pattern_1 = "git-[0-9]{4}-[0-9]{2}-[0-9]{2}-(?<commit>[a-z0-9]+)" # git-2023-01-02-cc2b1a325
            $file_pattern_2 = "N-\d+-g(?<commit>[a-z0-9]+)"                         # N-109751-g9a820ec8b
            $file_pattern = $file_pattern_1, $file_pattern_2 -join '|'
            $url_pattern = "git-([a-z0-9]+)"
            $file_match= [Regex]::Matches($ffmpeg_file, $file_pattern)
            $remote_match = [Regex]::Matches($remote_name, $url_pattern)
            $local_git = $file_match[0].groups['commit'].value
            $remote_git = $remote_match[0].groups[1].value

            if ($local_git -match $remote_git) {
                Write-Host "You are already using latest ffmpeg build -- $remote_name" -ForegroundColor Green
                $need_download = $false
            }
            else {
                Write-Host "Newer ffmpeg build available" -ForegroundColor Green
                $need_download = $true
            }
        }
        else {
            Wrong-Arch "ffmpeg"
        }
    }
    else {
        $need_download = $true
    }

    if ($need_download) {
        Download-Archive $remote_name $download_link
        Check-7z
        Extract-Archive $remote_name
    }
    Check-Autodelete $remote_name
}

function Read-KeyOrTimeout ($prompt, $key){
    $seconds = 9
    $startTime = Get-Date
    $timeOut = New-TimeSpan -Seconds $seconds

    Write-Host "$prompt " -ForegroundColor Green

    # Basic progress bar
    [Console]::CursorLeft = 0
    [Console]::Write("[")
    [Console]::CursorLeft = $seconds + 2
    [Console]::Write("]")
    [Console]::CursorLeft = 1

    while (-not [System.Console]::KeyAvailable) {
        $currentTime = Get-Date
        Start-Sleep -s 1
        Write-Host "#" -ForegroundColor Green -NoNewline
        if ($currentTime -gt $startTime + $timeOut) {
            Break
        }
    }
    if ([System.Console]::KeyAvailable) {
        $response = [System.Console]::ReadKey($true).Key
    }
    else {
        $response = $key
    }
    return $response.ToString()
}

#
# Main script entry point
#
if (Test-Admin) {
    Write-Host "Running script with administrator privileges" -ForegroundColor Yellow
}
else {
    Write-Host "Running script without administrator privileges" -ForegroundColor Red
}

try {
    Check-PowershellVersion
    # Sourceforge only support TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $global:progressPreference = 'silentlyContinue'
    Upgrade-Mpv
    Upgrade-Ytplugin
    Upgrade-FFmpeg
    Write-Host "Operation completed" -ForegroundColor Magenta
}
catch [System.Exception] {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
