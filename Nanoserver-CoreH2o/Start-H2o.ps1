$targetDir = "C:\"
$appDir = $targetDir + "\Apps"
$coreH2oDir = $appDir + "\H2o"
$Java = "$env:JAVA_HOME\bin\java.exe"

Set-Location -Path $coreNLPDir
&$Java -jar h2o.jar