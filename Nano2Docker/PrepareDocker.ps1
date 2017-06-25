Expand-Archive C:\docker.zip -DestinationPath $Env:ProgramFiles
##Remove-Item -Force docker.zip

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