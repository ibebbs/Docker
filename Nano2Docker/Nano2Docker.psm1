$prepareDockerBatch = @"
set LOCALAPPDATA=%USERPROFILE%\AppData\Local
set PSExecutionPolicyPreference=Unrestricted
powershell C:\PrepareDocker.ps1
"@

$prepareDockerPowershell = @"
Expand-Archive C:\docker.zip -DestinationPath $Env:ProgramFiles
##Remove-Item -Force docker.zip

$env:path += ";$env:ProgramFiles\docker"
[Environment]::SetEnvironmentVariable("PATH", $env:path)

netsh advfirewall firewall add rule name="Docker daemon" dir=in action=allow protocol=TCP localport=2375-2377
netsh advfirewall firewall add rule name="Docker chatter TCP" dir=in action=allow protocol=TCP localport=7946
netsh advfirewall firewall add rule name="Docker chatter UDP" dir=in action=allow protocol=UDP localport=7946
netsh advfirewall firewall add rule name="Docker network" dir=in action=allow protocol=UDP localport=4789

New-Item -Type File 'C:\ProgramData\docker\config\daemon.json' -Force

Add-Content 'C:\ProgramData\docker\config\daemon.json' '{ "hosts": ["tcp://0.0.0.0:2375", "npipe://"] }'

dockerd --register-service
Start-Service docker
"@

function Initialize-Nano2DockerImage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, HelpMessage="Specifies the path of the source media. If a local copy of the source media already exists, and it is specified using the BasePath parameter, then no copying is performed.")]
        [string]$MediaPath,
        [Parameter(Mandatory=$true, HelpMessage="Specifies the path where Nano Server files are copied from the source media. These files are not automatically deleted after running Edit-NanoServerImage or New-NanoServerImage. This enables you to copy the Nano Server files from the source media once with the MediaPath parameter and reuse the same files with the BasePath parameter when running Edit-NanoServerImage or New-NanoServerImage again.")]
        [string]$BasePath,
        [Parameter(Mandatory=$false, HelpMessage="Url to Docker zip file")]
        [string]$DockerUrl="https://download.docker.com/components/engine/windows-server/17.03/docker-17.03.0-ee.zip",
        [Parameter(Mandatory=$false, HelpMessage="Url to Docker zip file")]
        [string]$UpdateUrl="http://download.windowsupdate.com/d/msdownload/update/software/updt/2017/05/windows10.0-kb4023680-x64_de5502ce899738bedd5eb20f10cfe67ea26ff5b6.msu"
    )

    Import-Module "$($MediaPath)\NanoServer\NanoServerImageGenerator\NanoServerImageGenerator.psm1"

    if ($BasePath -eq "") {
        $BasePath = Convert-Path -Path .
    }

    $cred = Get-Credential -UserName '~\Administrator' -Message "Enter the administrator password Nano2Docker image:"
    
    $expand = "expand"
    
    $prepareDockerBatchFile = "$($BasePath)\PrepareDocker.bat"
    New-Item -Type File $prepareDockerBatchFile -Force
    Add-Content $prepareDockerBatchFile $prepareDockerBatch

    $prepareDockerPowershellFile = "$($BasePath)\PrepareDocker.ps1"
    New-Item -Type File $prepareDockerPowershellFile -Force
    Add-Content $prepareDockerPowershellFile $prepareDockerPowershell

    $docker = "$($BasePath)\docker.zip"
    Invoke-Webrequest -UseBasicparsing -Outfile $docker $DockerUrl
    
    $name = "Nano2Docker"
    $diskPath = "$($BasePath)\$($name).vhdx"

    if ($UpdateUrl -ne "") {
        New-Item -Type Directory "$($BasePath)\Updates" -Force
        Invoke-WebRequest -UseBasicparsing -Outfile "$($BasePath)\Updates\Update.msu" $UpdateUrl
        &$expand "$($BasePath)\Updates\Update.msu" "$($BasePath)\Updates" -F:*.cab -R
        $update = Get-ChildItem -Path "$($BasePath)\Updates" -Filter "*.cab" | 
            Where-Object {$_.Name -ne "WSUSSCAN.cab"} | 
            Select-Object FullName |
            ForEach-Object { '"' + $_.FullName + '"' }
        
        $servicingPath = [System.String]::Join(", ", $update)

        New-NanoServerImage -DeploymentType Guest -Edition Standard -MediaPath $MediaPath -BasePath $BasePath -TargetPath $diskPath -Containers -EnableRemoteManagementPort -CopyPath @($docker, $prepareDockerBatchFile, $prepareDockerPowershellFile) -SetupCompleteCommand "C:\PrepareDocker.bat" -ComputerName $name -AdministratorPassword $cred.Password -ServicingPackagePath $servicingPath
    } else {
        New-NanoServerImage -DeploymentType Guest -Edition Standard -MediaPath $MediaPath -BasePath $BasePath -TargetPath $diskPath -Containers -EnableRemoteManagementPort -CopyPath @($docker, $prepareDockerBatchFile, $prepareDockerPowershellFile) -SetupCompleteCommand "C:\PrepareDocker.bat" -ComputerName $name -AdministratorPassword $cred.Password
    }
}

function New-Nano2Docker {
    [CmdletBinding()]
    Param(
        [string]$MediaPath,
        [string]$BasePath,
        [string]$ImagePath,
        [string]$VMName="Nano2Docker",
        [string]$VMPath="C:\Users\Public\Documents\Hyper-V\Virtual Hard Disks"
    )

    Import-Module "$($MediaPath)\NanoServer\NanoServerImageGenerator\NanoServerImageGenerator.psm1"
    Import-Module Hyper-V

    $cred = Get-Credential -UserName '~\Administrator' -Message "Enter the administrator password for $($VMName):"
    $diskPath = "$($VMPath)\$($VMName).vhdx"

    Copy-Item -Path $ImagePath -Destination $diskPath

    Edit-NanoServerImage -MediaPath $MediaPath -BasePath $BasePath -TargetPath $diskPath -ComputerName $VMName -AdministratorPassword $cred.Password
    New-VM -Name $VMName -Generation 2 -VHDPath $diskPath -BootDevice "VHD" -Path $VMPath -SwitchName (Get-VMSwitch).Name

    $vm = Get-VM -VMName $VMName

    Set-VMProcessor -VM $vm -Count 4
    Set-VMMemory -VM $vm -DynamicMemoryEnabled $True -MaximumBytes 17179869184 -StartupBytes 2147483648
    Start-VM -VM $vm
    Wait-VM -VM $vm
}