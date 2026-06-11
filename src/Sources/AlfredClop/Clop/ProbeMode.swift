enum ProbeMode {
    static func response(discovery: ClopCLIDiscovery = ClopCLIDiscovery()) -> ClopDiagnostics {
        discovery.discover()
    }
}
