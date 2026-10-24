public enum RecordingTargetResolver {
    public static func resolve(
        frontmostProcessID: Int32?,
        lastExternalProcessID: Int32?,
        ownProcessID: Int32
    ) -> Int32? {
        if let frontmostProcessID, frontmostProcessID != ownProcessID {
            return frontmostProcessID
        }

        guard let lastExternalProcessID, lastExternalProcessID != ownProcessID else {
            return nil
        }
        return lastExternalProcessID
    }
}
