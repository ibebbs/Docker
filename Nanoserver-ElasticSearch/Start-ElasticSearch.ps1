$targetDir = "C:\"
$appDir = $targetDir + "\Apps"
$elasticSearchDir = $appDir + "\ElasticSearch"
$java = "$env:JAVA_HOME\bin\java.exe"

Set-Location -Path $elasticSearchDir
$startElasticSearch = "bin/ElasticSearch.bat"
&$startElasticSearch