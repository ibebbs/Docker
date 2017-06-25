Function New-DockerSwarm {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, HelpMessage="Path to the base NanoServer image and associated scripts/packages")]
        [string]$NanoServerPath,
        [Parameter(Mandatory=$true, HelpMessage="Directory in which to store VM files")]
        [string]$VMPath,
        [Parameter(Mandatory=$false, HelpMessage="Prefix for the new hyper-v instance names")]
        [string]$VMPrefix="b2n",
        [Parameter(Mandatory=$false, HelpMessage="Number of manager nodes to create")]
        [int]$ManagerNodes=1,
        [Parameter(Mandatory=$false, HelpMessage="Number of worker nodes to create")]
        [int]$WorkerNodes=3,
        [Parameter(Mandatory=$false, HelpMessage="Name of the overlay network")]
        [string]$NetworkName="boot2nano-net",
        [Parameter(Mandatory=$false, HelpMessage="Number of worker nodes to create")]
        [string]$DockerUrl="https://download.docker.com/components/engine/windows-server/17.03/docker-17.03.0-ee.zip"
    )
    
    Import-Module "C:\NanoServer\NanoServerImageGenerator\NanoServerImageGenerator.psm1"
    Import-Module Hyper-V

    $docker = "docker.exe"
    $cred = Get-Credential -UserName '~\Administrator' -Message 'Enter the administrator password for the swarm:'   
    $managerIPAddress = $null
    $managerToken = $null
    $workerToken = $null

    Invoke-Webrequest -UseBasicparsing -Outfile docker.zip $DockerUrl
    
    For ($managerCount = 0; $managerCount -lt $ManagerNodes; $managerCount++) {
        $managerName = "$($VMPrefix)-mngr-$($managerCount)"
        $managerDisk = "$($managerName).vhdx"
        $managerDiskPath = "$($VMPath)\$($managerName)\$($managerDisk)"

        Write-Output "Creating manager node named '$($managerName)' at '$($managerDiskPath)'"
        
        New-NanoServerImage -DeploymentType Guest -Edition Standard -BasePath $NanoServerPath -TargetPath $managerDiskPath -Containers -EnableRemoteManagementPort -CopyPath @("docker.zip", "$($NanoServerPath)\Scripts\PrepareDocker.bat", "$($NanoServerPath)\Scripts\PrepareDocker.ps1") -SetupCompleteCommand "C:\PrepareDocker.bat" -ComputerName $managerName -AdministratorPassword $cred.Password
    
        New-VM -Name $managerName -Generation 2 -VHDPath $managerDiskPath -BootDevice "VHD" -Path $VMPath -SwitchName (Get-VMSwitch).Name
        
        $vm = Get-VM -VMName $managerName

        Set-VMProcessor -VM $vm -Count 4
        Set-VMMemory -VM $vm -DynamicMemoryEnabled $True -MaximumBytes 17179869184 -StartupBytes 2147483648
        Start-VM -VM $vm
        Wait-VM -VM $vm
        
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
            ## Create overlay network swarm            
            Write-Output "Initializing overlay network named '$($NetworkName)'"
            $params = @(
                "-H $($ipAddress)", `
                "network", `
                "create", `
                "--driver=overlay", `
                $NetworkName
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
        
        New-NanoServerImage -DeploymentType Guest -Edition Standard -BasePath $NanoServerPath -TargetPath $workerDiskPath -Containers -EnableRemoteManagementPort -CopyPath @("docker.zip", "$($NanoServerPath)\Scripts\PrepareDocker.bat", "$($NanoServerPath)\Scripts\PrepareDocker.ps1") -SetupCompleteCommand "C:\PrepareDocker.bat" -ComputerName $workerName -AdministratorPassword $cred.Password
    
        New-VM -Name $workerName -Generation 2 -VHDPath $workerDiskPath -BootDevice "VHD" -Path $VMPath -SwitchName (Get-VMSwitch).Name
        
        $vm = Get-VM -VMName $workerName

        Set-VMProcessor -VM $vm -Count 4
        Set-VMMemory -VM $vm -DynamicMemoryEnabled $True -MaximumBytes 17179869184 -StartupBytes 2147483648
        Start-VM -VM $vm
        Wait-VM -VM $vm
        
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


