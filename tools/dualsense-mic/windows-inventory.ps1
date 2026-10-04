# Read-only inventory for the later Windows comparison. No driver installation or microphone activation.
# Review the local output before sharing it: PnP instance IDs can contain device identifiers.
$ErrorActionPreference = 'Stop'
$taskDevices = Get-PnpDevice -PresentOnly | Where-Object {
    $_.InstanceId -match 'VID_054C.*PID_0CE6' -or $_.FriendlyName -match 'DualSense|Wireless Controller'
}
$taskResults = foreach ($taskDevice in $taskDevices) {
    $taskProperties = @{}
    foreach ($taskKey in @('DEVPKEY_Device_Service', 'DEVPKEY_Device_DriverInfPath', 'DEVPKEY_Device_DriverVersion', 'DEVPKEY_Device_DriverProvider')) {
        $taskValue = Get-PnpDeviceProperty -InstanceId $taskDevice.InstanceId -KeyName $taskKey -ErrorAction SilentlyContinue
        $taskProperties[$taskKey] = $taskValue.Data
    }
    [pscustomobject]@{
        Name = $taskDevice.FriendlyName
        Class = $taskDevice.Class
        Status = $taskDevice.Status
        InstanceId = $taskDevice.InstanceId
        Driver = $taskProperties
    }
}
@($taskResults) | ConvertTo-Json -Depth 4
