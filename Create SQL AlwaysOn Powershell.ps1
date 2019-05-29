################################################################################
#                         vpc 192.168.0.0/16                                   #
#                                                                              #
#     ####################                   ####################              #
#     #                  #                   #                  #              #
#     #     Public       #                   #     Private      #              #
#     #   ###########    #                   #    ###########   #              #
#     #   #         #    #                   #    #         #   #              #
#     #   #         #    #                   #    #         #   #              #
#     #   #  WEB    #    #-------            #    #Database #   #              #
#     #   #         #    #      |            #    #         #   #              #
#     #   ###########    #      |            #    ###########   #              #
#     #                  #      |            #                  #              #
#     # 192.168.1.0/24   #      |            # 192.168.2.0/24   #              #
#     # ##################      |            ####################              #
#          #                 ########                |                         #
#       #######              #      #                |                         #
#       #     #              #Route #-----------------                         #
#       # IG  #--------------#Table #                                          #
#       #  |  #              #      #                                          #
###########|#####################################################################
#          |
#          |

Param 
    (
        [string] [parameter(mandatory=$true)] $DomainName, 
        [string] [parameter(mandatory=$false)] $VPCCIDR = '192.168.1.0/24',
        [string] [parameter(mandatory=$false)] $PublicSubnetCIDR = '192.168.1.0/24',
        [string] [parameter(mandatory=$false)] $PrivateSubnetCIDR ='192.168.2.0/24',
        [string] [parameter(mandatory=$true)] $KeyPair,
        [string] [parameter(mandatory=$true)] $InstanceType
    )


# Functions



# End Functions

#TODO: Rmeove Hardcoded Configuration
$DomainName = 'app2.aws.mad'
$VPCCIDR = '192.168.0.0/16'
$PublicSubnetCIDR = '192.168.1.0/24'
$PrivateSubnetCIDR ='192.168.2.0/24'
$KeyPair = 'All Servers'
$InstanceType = 'm5.large'


# Create a New VPC


$VPC = New-EC2VPC -CidrBlock $VPCCIDR
Start-Sleep -s 15 # Takes some time
$VPC.Tag ="SQLVPC"


#Configure DHCP for the VPC
$Domain = New-object Amazon.EC2.Model.DhcpConfiguration
$Domain.Key = 'domain-name'
$Domain.Value = $DomainName

$DNS = New-object Amazon.EC2.Model.DhcpConfiguration
$DNS.Key = 'domain-name-servers'
$DNS.Value = 'AmazonProvidedDNS'

$DHCP = New-EC2DHCPOption -DhcpConfiguration $Domain, $DNS
Register-EC2DhcpOption -DhcpOptionsId $DHCP.DhcpOptionsId -VpcId $vpc.VpcId


# Pick the first availablity zone in the region
$AvailabilityZones = Get-EC2AvailabilityZone
$AvailabilityZone = $AvailabilityZones[0].ZoneName

#Create and tag the Public Subnet
$PublicSubnet = New-Ec2Subnet -VpcId $VPC.VpcId -cidrBlock $PublicSubnetCIDR -AvailabilityZone $AvailabilityZone
Start-Sleep -s 15 # This can take a few seconds
$Tag = New-Object Amazon.EC2.Model.Tag
$Tag.Key = 'Name'
$Tag.Value = 'Public'
New-Ec2Tag -ResourceId $PublicSubnet.SubnetId -Tag $Tag

# Create and Tag the Private Subnet
$PrivateSubnet = New-EC2Subnet -VpcId $vpc.VpcId -CidrBlock $PrivateSubnetCIDR -AvailabilityZone $AvailabilityZone
Start-Sleep -s 15 # This can take a few seconds
$Tag = New-Object Amazon.EC2.Model.Tag
$Tag.Key = 'Name'
$Tag.Value = 'Private'
New-Ec2Tag -ResourceId $PrivateSubnet.SubnetId -Tag $Tag

# Add Internet Gateway and configure Route Table
$InternetGateway = New-EC2InternetGateway
Add-EC2InternetGateway -InternetGatewayId $InternetGateway.InternetGatewayId -VpcId $VPC.VpcId

#Create a new Route Table and associate with Public Subnet
$PublicRouteTable = New-Ec2RouteTable -VpcId $VPC.VpcId
New-EC2Route -RouteTableId $PublicRouteTable.RouteTableId -DestinationCidrBlock '0.0.0.0/0' -GatewayId $InternetGateway.InternetGatewayId
$NoEcho = Register-EC2RouteTable -RouteTableId $PublicRouteTable.RouteTableId -SubnetId $PublicSubnet.SubnetId

#Configure ACL's
#Create New ACL for the Public Subnet
$PublicAcl = New-EC2NetworkAcl -VpcId $VPC.VpcId

New-EC2NetworkAclEntry -NetworkAclId $PublicAcl.NetworkAclId -RuleNumber 50 -CidrBlock $VPCCIDR -Egress $false -PortRange_From 80 -PortRange_To 80 -Protocol 6 -RuleAction 'Deny'
New-EC2NetworkAclEntry -NetworkAclId $PublicAcl.NetworkAclId -RuleNumber 50 -CidrBlock $VPCCIDR -Egress $true -PortRange_From 49152 -PortRange_To 65535 -Protocol 6 -RuleAction 'Deny'
New-EC2NetworkAclEntry -NetworkAclId $PublicAcl.NetworkAclId -RuleNumber 100 -CidrBlock '0.0.0.0/0' -Egress $false -PortRange_From 80 -PortRange_To 80 -Protocol 6 -RuleAction 'Allow'
New-EC2NetworkAclEntry -NetworkAclId $PublicAcl.NetworkAclId -RuleNumber 100 -CidrBlock '0.0.0.0/0' -Egress $true -PortRange_From 49152 -PortRange_To 65535 -Protocol 6 -RuleAction 'Allow'
New-EC2NetworkAclEntry -NetworkAclId $PublicAcl.NetworkAclId -RuleNumber 200 -CidrBlock $PrivateSubnetCIDR -Egress $true -PortRange_From 1433 -PortRange_To 1433 -Protocol 6 -RuleAction 'Allow'
New-EC2NetworkAclEntry -NetworkAclId $PublicAcl.NetworkAclId -RuleNumber 300 -CidrBlock '0.0.0.0/0' -Egress $false -PortRange_From 3389 -PortRange_To 3389 -Protocol 6 -RuleAction 'Allow'

#Associate the ACL to the Public Subnet
$VPCFilter = New-Object Amazon.EC2.Model.Filter
$VPCFilter.Name = 'vpc-id'
$VPCFilter.Values = $VPC.VpcId
$DefaultFilter = New-Object Amazon.EC2.Model.Filter
$DefaultFilter.Name = 'default'
$DefaultFilter.Value = 'true'
$OldAcl = (Get-EC2NetworkAcl -Filter $VPCFilter, $DefaultFilter)
$OldAssociation = $OldACL.Associations | Where-Object { $_.SubnetId -eq $PublicSubnet.SubnetId}
$NoEcho = Set-EC2NetworkAclAssociation -AssociationId $OldAssociation.NetworkAclAssociationId -NetworkAclId $PublicACL.NetworkAclId

# Log the most common ID's
write-host "The VPC ID is: "  $VPC.VpcId
write-host "The Public Subnet ID is: " $PublicSubnet.SubnetId
Write-Host "The Private Subnet ID is: " $PrivateSubnet.SubnetId

#VPC SETUP COMPLETE
######################################################################################################################
#Launch EC2 Windows Server using CPU Optimisaiton
$instance = aws ec2 run-instances --image-id "ami-08a92ed64caa44b84" --instance-type $InstanceType --cpu-options "CoreCount=1,ThreadsPerCore=1" --key-name $KeyPair --subnet-id $PublicSubnet.SubnetId

#Get the Instance ID from the new instance
$InstanceId = $Instance.Item(6) # Item 6 in the JSON output
$separator = ": " # Split the strinfg on the seperator
$option = [System.StringSplitOptions]::RemoveEmptyEntries
$InstanceId = $InstanceID.split($separator,3,$option)
$instanceId =  $InstanceID[1] 
$instanceId = $InstanceId.Replace('",',"")
$instanceId = $InstanceId.Replace('"',"")
write-host "The Instance ID is: "$InstanceId

# Check for EC2 Success Launch
do
{
    $status = Get-EC2InstanceStatus -InstanceId $instanceId
    write-host $status.Status.Status.ToString()
    Start-Sleep -s 5
}
until ($status.Status.Status = "OK")
Write-Host $InstanceId "Status: ok"



# Attached SQL Media Volume to instance

# Extract the SQL Media

# Run SQL Installation