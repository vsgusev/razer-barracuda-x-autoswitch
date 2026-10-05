# Razer Barracuda X 2.4: headphones on -> sound goes to them, off -> back to the previous device.
# Windows can't tell whether the headphones are on: the dongle stays present either way.
# The dongle reports it in a vendor HID packet, which is what we listen to.

$HeadphonesName = 'Razer Barracuda X 2.4'
$DongleHid      = 'HID\VID_1532&PID_0550&MI_03&COL02\*'
$SpeakersFile   = "$PSScriptRoot\speakers.txt"

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

[ComImport, Guid("f8679f50-850a-41cf-9c72-430f290290c8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPolicyConfig {
    int GetMixFormat(); int GetDeviceFormat(); int ResetDeviceFormat(); int SetDeviceFormat();
    int GetProcessingPeriod(); int SetProcessingPeriod(); int GetShareMode(); int SetShareMode();
    int GetPropertyValue(); int SetPropertyValue();
    [PreserveSig] int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string id, int role);
}
[ComImport, Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")] class CPolicyConfigClient {}

[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {
    int Activate(); int OpenPropertyStore();
    [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
}
[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {
    int EnumAudioEndpoints();
    [PreserveSig] int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice dev);
}
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator {}

public static class AudioSwitch {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);

    public static string GetDefaultOutput() {
        IMMDevice dev;
        if (((IMMDeviceEnumerator)new MMDeviceEnumerator()).GetDefaultAudioEndpoint(0 /* render */, 1 /* multimedia */, out dev) != 0) return null;
        string id;
        dev.GetId(out id);
        return id;
    }

    // All three roles: console, multimedia, communications (Discord, Zoom, etc.)
    public static void SetDefaultOutput(string id) {
        var pc = (IPolicyConfig)new CPolicyConfigClient();
        for (int role = 0; role < 3; role++) Marshal.ThrowExceptionForHR(pc.SetDefaultEndpoint(id, role));
    }

    public static FileStream OpenHid(string path) {
        var h = CreateFile(path, 0x80000000 /* GENERIC_READ */, 3 /* share read|write */, IntPtr.Zero, 3 /* OPEN_EXISTING */, 0, IntPtr.Zero);
        if (h.IsInvalid) throw new IOException("Cannot open " + path + ", error " + Marshal.GetLastWin32Error());
        return new FileStream(h, FileAccess.Read, 1, false);
    }

    // Blocks until a connection status packet: 02 .. [12..14] = 20-02-01, [15] = 1 (on) / 0 (off)
    public static bool WaitHeadphonesOn(FileStream fs) {
        var buf = new byte[64];
        while (true) {
            int n = fs.Read(buf, 0, buf.Length);
            if (n >= 16 && buf[0] == 0x02 && buf[12] == 0x20 && buf[13] == 0x02 && buf[14] == 0x01)
                return buf[15] == 1;
        }
    }
}
'@

$RenderKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'

function Test-Active($id) {
    $key = "$RenderKey\$($id.Split('.')[-1])"
    (Test-Path $key) -and (((Get-ItemProperty $key).DeviceState -band 0xF) -eq 1)
}

function Find-Headphones {
    foreach ($key in Get-ChildItem $RenderKey) {
        $id = '{0.0.0.00000000}.' + $key.PSChildName
        $device = (Get-ItemProperty "$($key.PSPath)\Properties").'{b3f8fa53-0004-438e-9003-51a46e139bfc},6'
        if ($device -eq $HeadphonesName -and (Test-Active $id)) { return $id }
    }
}

function Switch-ToHeadphones {
    $headphones = Find-Headphones
    if (-not $headphones) { return }
    $current = [AudioSwitch]::GetDefaultOutput()
    if ($current -and $current -ne $headphones) { Set-Content $SpeakersFile $current }
    [AudioSwitch]::SetDefaultOutput($headphones)
}

function Switch-ToSpeakers {
    if (-not (Test-Path $SpeakersFile)) { return }
    $speakers = (Get-Content $SpeakersFile -TotalCount 1)
    if ($speakers -and (Test-Active $speakers)) { [AudioSwitch]::SetDefaultOutput($speakers) }
}

# The dongle only reports changes, its current state can't be queried.
# Headphones still being the default at startup almost always means the PC
# was shut down with them on, and they are off by now.
$headphones = Find-Headphones
if ($headphones -and [AudioSwitch]::GetDefaultOutput() -eq $headphones) { Switch-ToSpeakers }

while ($true) {
    $hid = Get-PnpDevice -PresentOnly -InstanceId $DongleHid -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $hid) { Start-Sleep -Seconds 5; continue }

    $path = '\\?\' + ($hid.InstanceId -replace '\\', '#') + '#{4d1e55b2-f16f-11cf-88cb-001111000030}'
    $fs = $null
    try {
        $fs = [AudioSwitch]::OpenHid($path)
        while ($true) {
            if ([AudioSwitch]::WaitHeadphonesOn($fs)) { Switch-ToHeadphones } else { Switch-ToSpeakers }
        }
    } catch {
        # Dongle unplugged or re-enumerated after sleep: reopen
        Start-Sleep -Seconds 2
    } finally {
        if ($fs) { $fs.Dispose() }
    }
}
