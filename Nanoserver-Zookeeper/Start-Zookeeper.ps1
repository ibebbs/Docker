$targetDir = "C:\"
$appDir = $targetDir + "\Apps"
$dataDir = $targetDir + "\Data"
$zookeeperDir = $appDir + "\Zookeeper"
$zookeeperDataDir = $dataDir + "\Zookeeper"
$zookeeper = $zookeeperDir + "\bin\zkServer.cmd"

Set-Location -Path $zookeeperDir
&$zookeeper