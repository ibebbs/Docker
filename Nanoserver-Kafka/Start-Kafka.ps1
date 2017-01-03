$targetDir = "C:\"
$appDir = $targetDir + "\Apps"
$dataDir = $targetDir + "\Data"
$kafkaDir = $appDir + "\Kafka"
$kafkaDataDir = $dataDir + "\Kafka"
$kafka = $kafkaDir + "\bin\windows\kafka-server-start.bat"

Set-Location -Path $kafkaDir
&$kafka  .\config\server.properties