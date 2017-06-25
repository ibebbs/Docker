$cred = Get-Credential -UserName '~\Administrator' -Message 'Enter the administrator password for the swarm:'

Edit-NanoServerImage -TargetPath .\NanoServer.wim -ServicingPackagePath .\Updates\Windows10.0-KB4023680-x64.cab

New-NanoServerImage -DeploymentType Guest -Edition Standard -BasePath .\ -TargetPath D:\NanoServer\B2N1\B2N1.vhdx -Containers -EnableRemoteManagementPort -CopyPath .\Scripts\PrepareDocker.ps1 -SetupCompleteCommand @("powershell.exe -Command C:\PrepareDocker.ps1") -ComputerName B2N1
New-VM -Name B2N1 -Generation 2 -VHDPath "D:\NanoServer\B2N1\B2N1.vhdx" -BootDevice "VHD" -Path D:\NanoServer -SwitchName (Get-VMSwitch).Name
Set-VMProcessor -VMName B2N1 -Count 4
Set-VMMemory -VMName B2N1 -DynamicMemoryEnabled $True -MaximumBytes 17179869184 -StartupBytes 2147483648
Start-VM -VMName B2N1
Wait-VM -VMName B2N1