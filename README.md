# cst8918-w26-A05-naveedhossain

graph TD

Internet((Internet)) --> PublicIP[Public IP]
PublicIP --> NIC[Network Interface (NIC)]
NIC --> VM[Virtual Machine<br/>Ubuntu + Apache]
VM --> Subnet[Subnet<br/>10.0.1.0/24]
Subnet --> VNet[Virtual Network<br/>10.0.0.0/16]
VNet --> RG[Resource Group]
