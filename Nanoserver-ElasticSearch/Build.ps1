## Download sources
$zipUri = "http://homeserver/download/7z1604-x64.exe" # http://www.7-zip.org/a/7z1604-x64.exe";
$javaUri = "http://homeserver/download/jre-8u111-windows-x64.tar.gz" # "http://download.oracle.com/otn-pub/java/jdk/8u111-b14/jre-8u111-windows-x64.tar.gz"
$elasticSearchUri = "http://homeserver/download/elasticsearch-5.3.2.zip" # "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-5.3.2.zip"
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
$buildElasticSearchDir = $biuldAppDir + "\ElasticSearch"

## Temp files
$zipInstaller = $tmpDir + "\7zInstaller.exe"
$jreGzip = $tmpDir + "\Jre.tar.gz"
$jreTar = $tmpDir + "\Jre.tar"
$elasticSearchZip = $tmpDir + "\ElasticSearch.zip"

## Target locations
$targetDir = "C:\"
$appDir = $targetDir + "\Apps"
$dataDir = $targetDir + "\Data"
$jreDir = $appDir + "\Jre"
$elasticSearchDir = $appDir + "\ElasticSearch"

## Executables
$zip = $buildZipDir + "\7z.exe"
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

function Get-ElasticSearch()
{
    Invoke-WebRequest -Uri $elasticSearchUri -OutFile $elasticSearchZip
    Expand-Directory $elasticSearchZip $buildElasticSearchDir

    ## Above will expand to a directory containing version name which we want to remove
    ## so we'll move everything up a directory
    $folder = Get-ChildItem -Path $buildElasticSearchDir -Filter "elasticsearch-*"
    Get-ChildItem -Path $folder.FullName -Recurse | Move-Item -destination $buildElasticSearchDir -Force
        
    Remove-Item -Path $folder.FullName -Force
    Remove-Item -Path $elasticSearchZip -Force
}

function Initialize-ElasticSearch()
{
    $configFile = $buildElasticSearchDir + '\config\elasticsearch.yml'

    $config = [IO.File]::ReadAllText($configFile) `
        -replace "#http.port: 9200", "http.port: 9200" `
        -replace "#network.host: 192.168.0.1", "network.host: 0.0.0.0"
    [IO.File]::WriteAllText($configFile, $config)
}

function New-DockerImage()
{
    Build-ContainerImage -Path $buildDir -Repository "ibebbs/nanoelastic:latest"
}


# Setup directory structure
#New-TempPath
#New-RootPath

# Install required tools
#Install-DockerModule
#Install-7zip

# Get components
#Get-Java
Get-ElasticSearch

# Configure components
Initialize-ElasticSearch

# Build docker image
New-DockerImage

# Cleanup
#Remove-DockerModule
#Remove-7zip
#Remove-TempPath
#Remove-RootPath
