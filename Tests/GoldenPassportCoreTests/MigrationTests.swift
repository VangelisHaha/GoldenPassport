import Testing

struct MigrationImportTests {
    @Test func migrationImportCompatibility() throws {
        try MigrationFixtures.verify()
    }
}
