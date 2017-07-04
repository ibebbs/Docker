$prepareDockerBatch = @'
set LOCALAPPDATA=%USERPROFILE%\AppData\Local
set PSExecutionPolicyPreference=Unrestricted
powershell C:\PrepareDocker.ps1
'@

$prepareDockerPowershell = @'
Expand-Archive C:\docker.zip -DestinationPath $Env:ProgramFiles
Remove-Item -Force docker.zip

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
'@

function Initialize-Nano2DockerImage {
    [CmdletBinding(DefaultParameterSetName="WebUpdate")]
    Param(
        [Parameter(Mandatory=$true, HelpMessage="Specifies the path of the source media. If a local copy of the source media already exists, and it is specified using the BasePath parameter, then no copying is performed.")]
        [string]$MediaPath,
        [Parameter(Mandatory=$true, HelpMessage="Specifies the path where Nano Server files are copied from the source media and additional files created.")]
        [string]$BuildPath,
        [Parameter(Mandatory=$false, HelpMessage="Url to Docker zip file")]
        [string]$DockerUrl="https://download.docker.com/components/engine/windows-server/17.03/docker-17.03.0-ee.zip",
        [Parameter(Mandatory=$false, HelpMessage="Url to Docker zip file", ParameterSetName="WebUpdate")]
        [string]$UpdateUrl="http://download.windowsupdate.com/d/msdownload/update/software/updt/2017/05/windows10.0-kb4023680-x64_de5502ce899738bedd5eb20f10cfe67ea26ff5b6.msu",
        [Parameter(Mandatory=$false, HelpMessage="Url to Docker zip file", ParameterSetName="FileUpdate")]
        [string]$UpdateFile,        
        [Parameter(Mandatory=$false, HelpMessage="Password for the Administrator account of the Nano2Docker image")]
        [SecureString]$Password
    )

    Import-Module "$($MediaPath)\NanoServer\NanoServerImageGenerator\NanoServerImageGenerator.psm1"

    if ($BuildPath -eq "") {
        $BuildPath = Convert-Path -Path .
    }

    if (($Password -eq $null) -or ($Password -eq "")) {
        $cred = Get-Credential -UserName '~\Administrator' -Message "Enter the administrator password Nano2Docker image:"
        $Password = $cred.Password
    }
    
    $expand = "expand"

    Write-Host "Creating files for Nano2Docker Image"

    $prepareDockerBatchFile = "$($BuildPath)\PrepareDocker.bat"
    New-Item -Type File $prepareDockerBatchFile -Force
    Add-Content $prepareDockerBatchFile $prepareDockerBatch

    $prepareDockerPowershellFile = "$($BuildPath)\PrepareDocker.ps1"
    New-Item -Type File $prepareDockerPowershellFile -Force
    Add-Content $prepareDockerPowershellFile $prepareDockerPowershell

    Write-Host "Downloading docker from $($DockerUrl)"

    $docker = "$($BuildPath)\docker.zip"
    Invoke-Webrequest -UseBasicparsing -Outfile $docker $DockerUrl
    
    $name = "Nano2Docker"
    $diskPath = "$($BuildPath)\$($name).vhdx"

    if ($psCmdlet.ParameterSetName -eq "WebUpdate") {
        New-Item -Type Directory "$($BuildPath)\Updates" -ErrorAction SilentlyContinue
        $UpdateFile = "$($BuildPath)\Updates\Update.msu"

        Write-Host "Downloading update file from $($UpdateUrl) to $($UpdateFile)"
        Invoke-WebRequest -UseBasicparsing -Outfile $UpdateFile $UpdateUrl
    } else {
        Write-Host "Copying update file from $($UpdateFile) to $($BuildPath)\Updates\Update.msu"
        Copy-Item $UpdateFile -Destination "$($BuildPath)\Updates\Update.msu" -Force
        $UpdateFile = "$($BuildPath)\Updates\Update.msu"
    }
    
    Write-Host "Expanding updates from $($UpdateFile)"
    &$expand $UpdateFile "$($BuildPath)\Updates" -F:*.cab -R
    $update = @(Get-ChildItem -Path "$($BuildPath)\Updates" -Filter "*.cab" | 
        Where-Object {$_.Name -ne "WSUSSCAN.cab"} | 
        Select-Object FullName |
        ForEach-Object { $_.FullName })
    
    $servicingPath = [System.String]::Join(", ", $update)

    Write-Host "Writing new NanoServerImage to $($diskPath)"
    New-NanoServerImage -DeploymentType Guest -Edition Standard -MediaPath $MediaPath -BasePath $BuildPath -TargetPath $diskPath -Containers -EnableRemoteManagementPort -CopyPath @($docker, $prepareDockerBatchFile, $prepareDockerPowershellFile) -SetupCompleteCommand "C:\PrepareDocker.bat" -ComputerName $name -AdministratorPassword $Password -ServicingPackagePath $servicingPath.ToString()
}

function New-Nano2Docker {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, HelpMessage="Specifies the path of the source media. If a local copy of the source media already exists, and it is specified using the BasePath parameter, then no copying is performed.")]
        [string]$MediaPath,
        [Parameter(Mandatory=$false, HelpMessage="Specifies the source Nano2Docker image created with Initialize-Nano2DockerImage")]
        [string]$ImagePath,
        [Parameter(Mandatory=$false, HelpMessage="Specifies the name for the virtual machine")]
        [string]$VMName="Nano2Docker",
        [Parameter(Mandatory=$false, HelpMessage="Specifies the directory in which to save the new VHDX")]
        [string]$VMPath="C:\Users\Public\Documents\Hyper-V\Virtual Hard Disks",
        [Parameter(Mandatory=$false, HelpMessage="Specifies the number of processors to allocate to the virtual machine")]
        [int]$VMProcessor=4,
        [Parameter(Mandatory=$false, HelpMessage="Password for the Administrator account of the virtual machine")]
        [SecureString]$Password
    )

    Import-Module "$($MediaPath)\NanoServer\NanoServerImageGenerator\NanoServerImageGenerator.psm1"
    Import-Module Hyper-V

    if (($Password -eq $null) -or ($Password -eq "")) {
        $cred = Get-Credential -UserName '~\Administrator' -Message "Enter the administrator password for $($VMName):"
        $Password = $cred.Password
    }
    
    $diskPath = "$($VMPath)\$($VMName).vhdx"

    Write-Host "Copying NanoServerImage from $($ImagePath) to $($diskPath)"
    Copy-Item -Path $ImagePath -Destination $diskPath

    Write-Host "Updating NanoServerImage"
    Edit-NanoServerImage -TargetPath $diskPath -ComputerName $VMName -AdministratorPassword $Password
    
    Write-Host "Creating new VM named $($VMName)"
    New-VM -Name $VMName -Generation 2 -VHDPath $diskPath -BootDevice "VHD" -Path $VMPath -SwitchName (Get-VMSwitch).Name

    $vm = Get-VM -VMName $VMName

    Set-VMProcessor -VM $vm -Count 4
    Set-VMMemory -VM $vm -DynamicMemoryEnabled $True -MaximumBytes 17179869184 -StartupBytes 2147483648
    
    Write-Host "Starting $($VMName)"
    Start-VM -VM $vm
    Wait-VM -VM $vm

    $ipAddress = $vm.NetworkAdapters[0].IPAddresses[0]

    Write-Host "$($VMName) running at $($ipAddress)"

    return $vm
}

Function New-Nano2DockerSwarm {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, HelpMessage="Specifies the path of the source media. If a local copy of the source media already exists, and it is specified using the BasePath parameter, then no copying is performed.")]
        [string]$MediaPath,
        [Parameter(Mandatory=$false, HelpMessage="Specifies the source Nano2Docker image created with Initialize-Nano2DockerImage")]
        [string]$ImagePath,
        [Parameter(Mandatory=$true, HelpMessage="Directory in which to store VM files")]
        [string]$VMPath,
        [Parameter(Mandatory=$false, HelpMessage="Prefix for the new hyper-v instance names")]
        [string]$VMPrefix="b2n",
        [Parameter(Mandatory=$false, HelpMessage="Number of manager nodes to create")]
        [int]$ManagerNodes=1,
        [Parameter(Mandatory=$false, HelpMessage="Number of worker nodes to create")]
        [int]$WorkerNodes=3,
        [Parameter(Mandatory=$false, HelpMessage="Number of worker nodes to create")]
        [string]$DockerUrl="https://download.docker.com/components/engine/windows-server/17.03/docker-17.03.0-ee.zip"
    )

    $docker = "docker.exe"
    $cred = Get-Credential -UserName '~\Administrator' -Message 'Enter the administrator password for the swarm:' 

    $managerIPAddress = $null
    $managerToken = $null
    $workerToken = $null
    
    For ($managerCount = 0; $managerCount -lt $ManagerNodes; $managerCount++) {
        $managerName = "$($VMPrefix)-mngr-$($managerCount)"
        $managerDisk = "$($managerName).vhdx"
        $managerDiskPath = "$($VMPath)\$($managerName)\$($managerDisk)"

        Write-Output "Creating manager node named '$($managerName)' at '$($managerDiskPath)'"

        $vm = New-Nano2Docker -MediaPath $MediaPath -ImagePath $ImagePath -VMName $managerName -VMPath $managerDiskPath -Password $cred.Password
                
        $ipAddress = $vm.NetworkAdapters[0].IPAddresses[0]

        if ($managerCount -eq 0) {
            $managerIPAddress = $ipAddress            
            Write-Output "Initializing swarm on '$($managerName)' node at '$($ipAddress)'"
            ## Initialise swarm
            $params = @(
                "-H $($ipAddress)", `
                "swarm", `
                "init", `
                "--advertise-addr=$($ipAddress)", `
                "--listen-addr=$($ipAddress):2377"
            )
            & $docker $params
            ## Get manager token
            $params = @(
                "-H $($ipAddress)", `
                "swarm", `
                "join-token", `
                "manager", `
                "-q"
            )
            $managerToken = & $docker $params
            ## Get worker token
            $params = @(
                "-H $($ipAddress)", `
                "swarm", `
                "join-token", `
                "worker", `
                "-q"
            )
            $workerToken = & $docker $params
        } else {
            Write-Output "'$($managerName)' node at '$($ipAddress)' joining swarm"
            ## Join swarm as manager
            $params = @(
                "-H $($ipAddress)", `
                "swarm", `
                "join", `
                "--token=$($managerToken)", `
                $managerIPAddress
            )
            & $docker $params
        }
    }
        
    For ($workerCount = 0; $workerCount -lt $WorkerNodes; $workerCount++) {
        $workerName = $VMPrefix + "-wrkr-" + $workerCount
        $workerDisk = $workerName + ".vhdx"
        $workerDiskPath = $VMPath + "\" + $workerDisk
        
        Write-Output "Creating worked node named '$($workerName)' at '$($workerDiskPath)'"
        
        $vm = New-Nano2Docker -MediaPath $MediaPath -ImagePath $ImagePath -VMName $workerName -VMPath $workerDiskPath -Password $cred.Password
                
        $ipAddress = $vm.NetworkAdapters[0].IPAddresses[0]

        ## Join swarm as manager
        $params = @(
            "-H $($ipAddress)", `
            "swarm", `
            "join", `
            "--token=$($workerToken)", `
            $managerIPAddress
        )
        & $docker $params
    }
}