import Foundation
import Vision

let req = VNClassifyImageRequest()
let revisions = VNClassifyImageRequest.supportedRevisions
FileHandle.standardError.write("supportedRevisions: \(revisions)\n".data(using: .utf8)!)
let rev = revisions.max() ?? VNClassifyImageRequestRevision1
let known = try VNClassifyImageRequest.knownClassifications(forRevision: rev)
print("REVISION \(rev)  TOTAL \(known.count)")
for k in known.map(\.identifier).sorted() { print(k) }
