## Download sources
$zipUri = "http://homeserver/download/7z1604-x64.exe" # http://www.7-zip.org/a/7z1604-x64.exe";
$javaUri = "http://homeserver/download/jre-8u111-windows-x64.tar.gz" # "http://download.oracle.com/otn-pub/java/jdk/8u111-b14/jre-8u111-windows-x64.tar.gz"
$neo4jUri = "http://homeserver/download/neo4j-community-3.1.3-windows.zip" # "http://info.neo4j.com/download-thanks.html?edition=community&release=3.1.3&flavour=winzip&_ga=1.115918662.1383524316.1490904367"
$dockerModuleUri = "http://homeserver/download/Docker.0.1.0.zip" # "https://github.com/Microsoft/Docker-PowerShell/releases/download/v0.1.0/Docker.0.1.0.zip"

## Build location
$buildDir = Get-Location
$tmpDir = $buildDir.Path + "\Temp"
$rootDir = $buildDir.Path + "\Root"
$biuldAppDir = $rootDir + "\Apps"
$buildDataDir = $rootDir + "\Data"
$buildDockerZip = $tmpDir + "\Docker.zip"
$buildDockerModule = $tmpDir + "\Docker"
$buildZipDir = $tmpDir + "\7zip"
$buildJreDir = $biuldAppDir + "\Jre"
$buildNeo4jDir = $biuldAppDir + "\Neo4j"
$buildNeo4jManagementDir = $buildNeo4jDir + "\bin\Neo4j-Management"
$buildNeo4jDataDir = $buildDataDir + "\Neo4j"

## Temp files
$zipInstaller = $tmpDir + "\7zInstaller.exe"
$jreGzip = $tmpDir + "\Jre.tar.gz"
$jreTar = $tmpDir + "\Jre.tar"
$neo4jZip = $tmpDir + "\Neo4j.zip"

## Target locations
$targetDir = "C:\"
$appDir = $targetDir + "\Apps"
$dataDir = $targetDir + "\Data"
$jreDir = $appDir + "\Jre"
$neo4jDir = $appDir + "\Neo4j"
$neo4jDataDir = $dataDir + "\Neo4j"

## Executables
$zip = $buildZipDir + "\7z.exe"
$neo4j = $neo4jDir + "\bin\neo4j.bat"
$docker = "docker"

function New-TempPath()
{
    if (!(Test-Path -Path $tmpDir))
    {
        New-Item $tmpDir -ItemType Directory
    }
}

function Remove-TempPath()
{
    Remove-Item $tmpDir -Recurse -Force
}

function New-RootPath()
{
    Remove-Item $rootDir -Recurse -Force 
    New-Item $rootDir -ItemType Directory
}

function Remove-RootPath()
{
    Remove-Item $rootDir -Recurse -Force 
}

function Expand-File($zipFile, $targetPath)
{
    $args = @("e", $zipFile, "-o$targetPath", '-y')
    &$zip $args | Out-Host
} 

function Expand-Directory($zipFile, $targetPath)
{
    $args = @("x", $zipFile, "-o$targetPath", '-aoa')
    &$zip $args | Out-Host
} 

function Install-DockerModule()
{
    Invoke-WebRequest -Uri $dockerModuleUri -OutFile $buildDockerZip
    Expand-Archive -Path $buildDockerZip -DestinationPath $buildDockerModule -Force

    Import-Module $buildDockerModule
}

function Remove-DockerModule()
{
    Remove-Module $buildDockerModule
}

function Install-7zip()
{
    $folder = New-Item $buildZipDir -ItemType Directory -Force
    Invoke-WebRequest -Uri $zipUri -OutFile $zipInstaller
    &$zipInstaller /S /D=$folder | Out-Null
    Remove-Item -Path $zipInstaller
}

function Remove-7zip()
{
    Remove-Item $buildZipDir -Recurse -Force
}

function Get-Java()
{
    Invoke-WebRequest -Uri $javaUri -OutFile $jreGzip
    Expand-File $jreGzip $tmpDir
    Expand-Directory $jreTar $buildJreDir

    ## Above will expand to a directory containing version name which we want to remove
    ## so we'll move everything up a directory
    $folder = Get-ChildItem -Path $buildJreDir -Filter "jre*"
    Get-ChildItem -Path $folder.FullName -Recurse | Move-Item -destination $buildJreDir -Force
    
    Remove-Item -Path $folder.FullName -Force
    Remove-Item -Path $jreGzip -Force
    Remove-Item -Path $jreTar -Force
}

function Get-Neo4j()
{
    Invoke-WebRequest -Uri $neo4jUri -OutFile $neo4jZip
    Expand-Directory $neo4jZip $buildNeo4jDir

    ## Above will expand to a directory containing version name which we want to remove
    ## so we'll move everything up a directory
    $folder = Get-ChildItem -Path $buildNeo4jDir -Filter "neo4j-*"
    Get-ChildItem -Path $folder.FullName -Recurse | Move-Item -destination $buildNeo4jDir -Force
        
    Remove-Item -Path $folder.FullName -Force
    Remove-Item -Path $neo4jZip -Force
}

function Initialize-Neo4j()
{
    New-Item -Path $buildDataDir -ItemType Directory -Force
    New-Item -Path $buildNeo4jDataDir -ItemType Directory -Force

    $neo4jDataLinuxDir = $buildNeo4jDataDir.Replace('\', '/')

    $configFile = $buildNeo4jDir + '\conf\neo4j.conf'

    $config = [IO.File]::ReadAllText($configFile) `
     -replace "#dbms.connectors.default_listen_address=0.0.0.0", "dbms.connectors.default_listen_address=0.0.0.0"

    [IO.File]::WriteAllText($configFile, $config)
}

function Limit-Neo4j()
{
    $setNeo4jEnvScript = $buildNeo4jManagementDir + "\Set-Neo4jEnv.ps1"
    
    $script = [IO.File]::ReadAllText($setNeo4jEnvScript) `
     -replace ', "Process"', ''

    [IO.File]::WriteAllText($setNeo4jEnvScript, $script)
}

function New-DockerImage()
{
    Build-ContainerImage -Path $buildDir -Repository "ibebbs/nanoneo:latest"
}


# Setup directory structure
New-TempPath
New-RootPath

# Install required tools
Install-DockerModule
Install-7zip

# Get components
Get-Java
Get-Neo4j
Initialize-Neo4j
Limit-Neo4j

# Build docker image
New-DockerImage

# Cleanup
Remove-DockerModule
Remove-7zip
Remove-TempPath
Remove-RootPath
