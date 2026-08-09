// SupabaseService.swift
// Omina
//
// Zentraler Supabase Client - Singleton für alle Services

import Foundation
import Supabase

final class SupabaseService {
    static let shared = SupabaseService()
    
    let client: SupabaseClient
    
    private init() {
        guard let url = URL(string: Secrets.supabaseURL) else {
            fatalError("Invalid Supabase URL in Secrets.swift")
        }

        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: Secrets.supabaseAnonKey
        )
    }
}