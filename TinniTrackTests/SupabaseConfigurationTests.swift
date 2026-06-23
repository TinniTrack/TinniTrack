import Foundation
import Testing
@testable import TinniTrack

struct SupabaseConfigurationTests {
    @Test
    func bundledProductionValuesResolveToProduction() {
        let environment = SupabaseConfiguration.currentEnvironment(
            bundleInfo: [
                "SUPABASE_URL": "https://kxskqyohcebixhjgzadp.supabase.co",
                "SUPABASE_ANON_KEY": "prod-anon-key",
                "SUPABASE_ENVIRONMENT": "Production"
            ],
            processEnvironment: [:]
        )

        #expect(environment.name == "Production")
        #expect(environment.isProduction == true)
        #expect(environment.hostDescription == "kxskqyohcebixhjgzadp.supabase.co")
    }

    @Test
    func bundledHostedDevValuesResolveToDevelopment() {
        let environment = SupabaseConfiguration.currentEnvironment(
            bundleInfo: [
                "SUPABASE_URL": "https://vhgbjeeoqmbqvxtstpcq.supabase.co",
                "SUPABASE_ANON_KEY": "dev-publishable-key",
                "SUPABASE_ENVIRONMENT": "Development"
            ],
            processEnvironment: [:]
        )

        #expect(environment.name == "Development")
        #expect(environment.isProduction == false)
        #expect(environment.hostDescription == "vhgbjeeoqmbqvxtstpcq.supabase.co")
    }

    @Test
    func bundledLocalhostValuesResolveToLocalWithoutExplicitEnvironment() {
        let environment = SupabaseConfiguration.currentEnvironment(
            bundleInfo: [
                "SUPABASE_URL": "http://127.0.0.1:54321",
                "SUPABASE_ANON_KEY": "local-anon-key"
            ],
            processEnvironment: [:]
        )

        #expect(environment.name == "Local")
        #expect(environment.isProduction == false)
        #expect(environment.hostDescription == "127.0.0.1")
    }

    @Test
    func processEnvironmentOverridesBundledValues() {
        let environment = SupabaseConfiguration.currentEnvironment(
            bundleInfo: [
                "SUPABASE_URL": "https://kxskqyohcebixhjgzadp.supabase.co",
                "SUPABASE_ANON_KEY": "prod-anon-key",
                "SUPABASE_ENVIRONMENT": "Production"
            ],
            processEnvironment: [
                "SUPABASE_URL": "https://vhgbjeeoqmbqvxtstpcq.supabase.co",
                "SUPABASE_ANON_KEY": "dev-publishable-key",
                "SUPABASE_ENVIRONMENT": "Development"
            ]
        )

        #expect(environment.name == "Development")
        #expect(environment.isProduction == false)
        #expect(environment.hostDescription == "vhgbjeeoqmbqvxtstpcq.supabase.co")
    }
}
