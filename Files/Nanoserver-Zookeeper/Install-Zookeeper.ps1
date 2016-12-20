## Download sources
$zipUri = "http://homeserver/download/7z1604-x64.exe" # http://www.7-zip.org/a/7z1604-x64.exe";
$nssmUri = "http://homeserver/download/nssm-2.24.zip" # "https://nssm.cc/release/nssm-2.24.zip"
$javaUri = "http://homeserver/download/jre-8u111-windows-x64.exe" # "http://download.oracle.com/otn-pub/java/jdk/8u111-b14/jre-8u111-windows-x64.exe"
$zookeeperUri = "http://homeserver/download/zookeeper-3.4.9.tar.gz" # "http://apache.mirrors.nublue.co.uk/zookeeper/zookeeper-3.4.9/zookeeper-3.4.9.tar.gz"
$kafkaUri = "http://homeserver/download/kafka_2.11-0.10.1.0.tgz" # "http://apache.mirror.anlx.net/kafka/0.10.1.0/kafka_2.11-0.10.1.0.tgz"

## Application locations
$appDir = "c:\Apps"
$zipDir = $appDir + "\7zip"
$nssmDir = $appDir + "\nssm"
$zookeeperDir = $appDir + "\Zookeeper"

## Data locations
$zookeeperDataDir = $zookeeperDir + "\Data"

## Application executables
$zip = $zipDir + "\7z.exe"
$nssm = $nssmDir + "\nssm.exe"
$zookeeper = $zookeeperDir + "\bin\zkServer.cmd"

function New-TempPath()
{
    if (!(Test-Path -Path C:\Temp))
    {
        New-Item c:\Temp -ItemType Directory
    }
}

function Expand-File($zipFile, $targetPath)
{
    $args = @("e", $zipFile, "-o$targetPath", '-y')
    &$zip $args
} 

function Expand-Directory($zipFile, $targetPath)
{
    $args = @("x", $zipFile, "-o$targetPath", '-aoa')
    &$zip $args
} 

function Install-7zip()
{
    New-Item "c:\Temp\7zip" -ItemType Directory -Force
    Invoke-WebRequest -Uri $zipUri -OutFile c:\Temp\7zip\7zip.exe
    &"C:\Temp\7zip\7zip.exe" /S /D=$zipDir | Out-Null
    Remove-Item -Path "c:\Temp\7zip\7zip.exe"
}

function Install-NSSM()
{
    New-Item "c:\Temp\NSSM" -ItemType Directory -Force
    Invoke-WebRequest -Uri $nssmUri -OutFile c:\Temp\NSSM\NSSM.zip

    Expand-Directory c:\Temp\NSSM\NSSM.zip c:\Temp\NSSM

    ## Above will expand to a directory containing version name which we want to remove
    ## so we'll move everything up a directory
    $folder = Get-ChildItem -Path c:\Temp\NSSM -Filter "nssm-*"
    Get-ChildItem -Path $folder.FullName -Recurse | Move-Item -destination c:\Temp\NSSM -Force

    New-Item $nssmDir -ItemType Directory -Force
    Copy-Item -Path "c:\Temp\NSSM\win64\nssm.exe" $nssm -Force
}

function Install-Java()
{
    New-Item c:\Temp\Java -ItemType Directory -Force
    Invoke-WebRequest -Uri $javaUri -OutFile c:\temp\Java\Java.exe

    Start-Process "C:\Temp\Java\Java.exe" -ArgumentList "INSTALL_SILENT=Enable INSTALLDIR=C:\Java\Jre AUTO_UPDATE=Disable WEB_JAVA=Disable WEB_ANALYTICS=Disable EULA=Disable REBOOT=Disable NOSTARTMENU=Enable SPONSORS=Disable REMOVEOUTOFDATEJRES=0" -NoNewWindow -Wait

    [Environment]::SetEnvironmentVariable("JAVA_HOME", "C:\Java\Jre", "Machine")
    
    Remove-Item -Path "C:\Temp\Java\Java.exe"
}

function Get-Zookeeper()
{
    New-Item c:\Temp\Zookeeper -ItemType Directory -Force
    Invoke-WebRequest -Uri $zookeeperUri -OutFile c:\temp\Zookeeper\Zookeeper.tar.gz
    Expand-File c:\temp\Zookeeper\Zookeeper.tar.gz c:\temp\Zookeeper
    Expand-Directory c:\temp\Zookeeper\Zookeeper.tar $zookeeperDir

    ## Above will expand to a directory containing version name which we want to remove
    ## so we'll move everything up a directory
    $folder = Get-ChildItem -Path $zookeeperDir -Filter "zookeeper-*"
    Get-ChildItem -Path $folder.FullName -Recurse | Move-Item -destination $zookeeperDir -Force
        
    Remove-Item -Path $folder.FullName
    Remove-Item -Path "c:\temp\Zookeeper" -Recurse
}

function Initialize-Zookeeper()
{
    New-Item -Path $zookeeperDataDir -ItemType Directory -Force
    $zookeeperDataLinuxDir = $zookeeperDataDir.Replace('\', '/')

    Copy-Item -Path ($zookeeperDir + '\conf\zoo_sample.cfg') -Destination ($zookeeperDir + '\conf\zoo.cfg') -Force

    $configFile = $zookeeperDir + '\conf\zoo.cfg'
    $logFile = $zookeeperDir + '\conf\log4j.properties'

    $config = [IO.File]::ReadAllText($configFile) -replace "dataDir=[\/\w]*", ("dataDir=" + $zookeeperDataLinuxDir)
    [IO.File]::WriteAllText($configFile, $config)

    $logProperties = [IO.File]::ReadAllText($logFile) -replace "#log4j.rootLogger=DEBUG, CONSOLE, ROLLINGFILE", "log4j.rootLogger=DEBUG, CONSOLE, ROLLINGFILE"
    [IO.File]::WriteAllText($logFile, $logProperties)
}

function Install-Zookeeper()
{
    &$nssm install Zookeeper $zookeeper | Out-Null
    &$nssm set Zookeeper AppDirectory $zookeeperDir | Out-Null

    &$nssm set Zookeeper DisplayName "Zookeeper" | Out-Null
    &$nssm set Zookeeper Description "Apache Zookeeper. Running from $zookeeperDir" | Out-Null
    &$nssm set Zookeeper Start SERVICE_AUTO_START | Out-Null
    &$nssm set Zookeeper ObjectName LocalSystem | Out-Null
    &$nssm set Zookeeper Type SERVICE_WIN32_OWN_PROCESS | Out-Null
}

function Start-Zookeeper()
{
    &$nssm start Zookeeper | Out-Null
}

function Stop-Zookeeper()
{
    &$nssm stop Zookeeper | Out-Null
}

#New-TempPath

Install-7zip
#Install-NSSM
#Install-Java

Get-Zookeeper
Initialize-Zookeeper
Install-Zookeeper
Start-Zookeeper
