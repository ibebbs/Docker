$prepareElasticsearchBatch = @'
set LOCALAPPDATA=%USERPROFILE%\AppData\Local
set PSExecutionPolicyPreference=Unrestricted
powershell C:\PrepareDocker.ps1
'@

$prepareElasticsearchPowershell = @'
$jreDirectory = "$($Env:ProgramFiles)\jre"
Expand-Archive C:\jre.zip -DestinationPath $jreDirectory
$folder = Get-ChildItem -Path $jreDirectory -Filter "jre*"
Get-ChildItem -Path $folder.FullName -Recurse | Move-Item -destination $buildJreDir -Force
Remove-Item -Path $folder.FullName -Force
Remove-Item -Force jre.zip

[Environment]::SetEnvironmentVariable("JAVA_HOME", $jreDirectory)

$elasticSearchDirectory = "$($Env:ProgramFiles)\elasticsearch"
Expand-Archive C:\elasticsearch.zip -DestinationPath $elasticSearchDirectory
$folder = Get-ChildItem -Path $elasticSearchDirectory -Filter "elasticsearch-*"
Get-ChildItem -Path $folder.FullName -Recurse | Move-Item -destination $elasticSearchDirectory -Force

Remove-Item -Path $folder.FullName -Force
Remove-Item -Force elasticsearch.zip

$configFile = "$($elasticSearchDirectory)\config\elasticsearch.yml"

$config = [IO.File]::ReadAllText($configFile) `
    -replace "#http.port: 9200", "http.port: 9200" `
    -replace "#network.host: 192.168.0.1", "network.host: 0.0.0.0"
[IO.File]::WriteAllText($configFile, $config)

netsh advfirewall firewall add rule name="ElasticSearch Client" dir=in action=allow protocol=TCP localport=9200
netsh advfirewall firewall add rule name="ElasticSearch Server" dir=in action=allow protocol=TCP localport=9300

$elasticSearch = "$($elasticSearchDirectory)\bin\service.bat install"

$service = Get-Service | Where-Object { $_.Name -like 'ElasticSearch*' }
Set-Service -StartupType Automatic $service
Start-Service $service
'@

function Initialize-Nano2ElasticSearchImage {
    [CmdletBinding(DefaultParameterSetName="WebUpdate")]
    Param(
        [Parameter(Mandatory=$true, HelpMessage="Specifies the path of the source media. If a local copy of the source media already exists, and it is specified using the BasePath parameter, then no copying is performed.")]
        [string]$MediaPath,
        [Parameter(Mandatory=$true, HelpMessage="Specifies the path where Nano Server files are copied from the source media and additional files created.")]
        [string]$BuildPath,
        [Parameter(Mandatory=$false, HelpMessage="Url to JRE zip file")]
        [string]$JreUrl="http://homeserver/download/jre1.8.0_111.zip",
        [Parameter(Mandatory=$false, HelpMessage="Url to ElasticSearch zip file")]
        [string]$ElasticSearchUrl="http://homeserver/download/elasticsearch-5.3.2.zip",
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
        $cred = Get-Credential -UserName '~\Administrator' -Message "Enter the administrator password Nano2ElasticSearch image:"
        $Password = $cred.Password
    }
    
    $expand = "expand"

    Write-Host "Creating files for Nano2ElasticSearch Image"

    $prepareElasticsearchBatchFile = "$($BuildPath)\PrepareElasticsearch.bat"
    New-Item -Type File $prepareElasticsearchBatchFile -Force
    Add-Content $prepareElasticsearchBatchFile $prepareElasticsearchBatch

    $prepareElasticsearchPowershellFile = "$($BuildPath)\PrepareElasticsearch.ps1"
    New-Item -Type File $prepareElasticsearchPowershellFile -Force
    Add-Content $prepareElasticsearchPowershellFile $prepareElasticsearchPowershell
    
    Write-Host "Downloading JRE from $ElasticSearchUrl"
    $jre = "$($BuildPath)\jre.zip"
    Invoke-Webrequest -UseBasicparsing -Outfile $jre $JreUrl

    Write-Host "Downloading Elasticsearch from $ElasticSearchUrl"
    $elasticsearch = "$($BuildPath)\elasticsearch.zip"
    Invoke-Webrequest -UseBasicparsing -Outfile $elasticsearch $ElasticSearchUrl    
    
    $name = "Nano2ES"
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
    New-NanoServerImage -DeploymentType Guest -Edition Standard -MediaPath $MediaPath -BasePath $BuildPath -TargetPath $diskPath -EnableRemoteManagementPort -CopyPath @($jre, $elasticsearch, $prepareElasticsearchBatchFile, $prepareElasticsearchPowershellFile) -SetupCompleteCommand "C:\PrepareElasticsearch.bat" -ComputerName $name -AdministratorPassword $Password -ServicingPackagePath $servicingPath.ToString()
}

function New-Nano2ElasticSearch {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, HelpMessage="Specifies the path of the source media. If a local copy of the source media already exists, and it is specified using the BasePath parameter, then no copying is performed.")]
        [string]$MediaPath,
        [Parameter(Mandatory=$false, HelpMessage="Specifies the source Nano2Docker image created with Initialize-Nano2DockerImage")]
        [string]$ImagePath,
        [Parameter(Mandatory=$false, HelpMessage="Specifies the name for the virtual machine")]
        [string]$VMName="Nano2Elk",
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

Function New-Nano2ElasticSearchCluster {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, HelpMessage="Specifies the path of the source media. If a local copy of the source media already exists, and it is specified using the BasePath parameter, then no copying is performed.")]
        [string]$MediaPath,
        [Parameter(Mandatory=$false, HelpMessage="Specifies the source Nano2Docker image created with Initialize-Nano2DockerImage")]
        [string]$ImagePath,
        [Parameter(Mandatory=$true, HelpMessage="Directory in which to store VM files")]
        [string]$VMPath,
        [Parameter(Mandatory=$false, HelpMessage="Prefix for the new hyper-v instance names")]
        [string]$VMPrefix="n2d",
        [Parameter(Mandatory=$false, HelpMessage="Number of manager nodes to create")]
        [int]$ManagerNodes=1,
        [Parameter(Mandatory=$false, HelpMessage="Number of worker nodes to create")]
        [int]$WorkerNodes=3
    )

    $docker = "docker.exe"
    $cred = Get-Credential -UserName '~\Administrator' -Message 'Enter the administrator password for the swarm:' 

    $managerIPAddress = $null
    $managerToken = $null
    $workerToken = $null
    
    For ($managerCount = 0; $managerCount -lt $ManagerNodes; $managerCount++) {
        $managerName = "$($VMPrefix)-mngr-$($managerCount)"
        $managerDiskPath = "$($VMPath)\$($managerName)"

        New-Item -ItemType Directory -Path $managerDiskPath -Force

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
        $workerName = "$($VMPrefix)-wrkr-$($workerCount)"
        $workerDiskPath = "$($VMPath)\$($workerName)"
        
        New-Item -ItemType Directory -Path $workerDiskPath -Force
        
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