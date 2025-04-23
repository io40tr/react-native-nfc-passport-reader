import CoreNFC
import Foundation
import OpenSSL
import React
import UIKit

@objc(NfcPassportReader)
class NfcPassportReader: NSObject {
  private let passportReader = PassportReader()
  private let passportUtil = PassportUtil()
  private let availableFiles: [String: DataGroupId] = [
    //"EF_CARD_ACCESS": .CardAccess,
    "EF_COM": .COM,
    "EF_SOD": .SOD,
    "EF_DG1": .DG1,
    "EF_DG2": .DG2,
    "EF_DG3": .DG3,
    "EF_DG4": .DG4,
    "EF_DG5": .DG5,
    "EF_DG6": .DG6,
    "EF_DG7": .DG7,
    "EF_DG8": .DG8,
    "EF_DG9": .DG9,
    "EF_DG10": .DG10,
    "EF_DG11": .DG11,
    "EF_DG12": .DG12,
    "EF_DG13": .DG13,
    "EF_DG14": .DG14,
    "EF_DG15": .DG15,
    "EF_DG16": .DG16
  ]

  @objc
  static func requiresMainQueueSetup() -> Bool {
    return true
  }

  @objc func isNfcSupported(
    _ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    if #available(iOS 13.0, *) {
      resolve(NFCNDEFReaderSession.readingAvailable)
    } else {
      resolve(false)
    }
  }

  @objc func startReading(
    _ options: NSDictionary, resolver resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    let bacKey = options["bacKey"] as? NSDictionary
    let includeImages = options["includeImages"] as? Bool
    let extraFiles = options["extraFiles"] as? [String] ?? []

    let documentNo = bacKey?["documentNo"] as? String
    let expiryDate = bacKey?["expiryDate"] as? String
    let birthDate = bacKey?["birthDate"] as? String

    if let documentNo = documentNo, let expiryDate = expiryDate, let birthDate = birthDate {
      if let birthDateFormatted = birthDate.convertToYYMMDD() {
        passportUtil.dateOfBirth = birthDateFormatted
      } else {
        reject("ERROR_INVALID_BIRTH_DATE", "Invalid birth date", nil)
        return
      }

      if let expiryDateFormatted = expiryDate.convertToYYMMDD() {
        passportUtil.expiryDate = expiryDateFormatted
      } else {
        reject("ERROR_INVALID_EXPIRY_DATE", "Invalid expiry date", nil)
        return
      }

      passportUtil.passportNumber = documentNo

      let mrzKey = passportUtil.getMRZKey()

      var tags: [DataGroupId] = [.COM, .DG1, .DG11, .SOD]

      if includeImages ?? false {
        tags.append(.DG2)
        tags.append(.DG5)
      }
      

      for file in extraFiles {
        if let dataGroupId = availableFiles[file], !tags.contains(dataGroupId) {
          tags.append(dataGroupId)
        }
      }

      let finalTags = tags 

      let customMessageHandler: (NFCViewDisplayMessage) -> String? = { displayMessage in
        switch displayMessage {
        case .requestPresentPassport:
          return "Hold your iPhone near an NFC-enabled ID Card / Passport."
        case .successfulRead:
          return "ID Card / Passport Successfully Read."
        case .readingDataGroupProgress(let dataGroup, let progress):
          let progressString = self.handleProgress(percentualProgress: progress)
          let readingDataString = "Read Data"
          return "\(readingDataString) \(dataGroup) ...\n\(progressString)"
        case .error(let error):
          return error.errorDescription
        default:
          return nil
        }
      }

      Task {
        do {
          let passport = try await self.passportReader.readPassport(
            mrzKey: mrzKey, tags: finalTags, customDisplayMessage: customMessageHandler)
          print("passport: \(passport)")

          let result: NSMutableDictionary = [
            "birthDate": passport.dateOfBirth.convertToYYYYMMDD(),
            "documentNo": passport.documentNumber,
            "expiryDate": passport.documentExpiryDate.convertToYYYYMMDD(),
            "gender": passport.gender,
            "identityNo": passport.personalNumber ?? "",
            "nationality": passport.nationality,
            "mrz": passport.passportMRZ,
          ]
          
        
          result["firstName"] = passport.firstName
          result["lastName"] = passport.lastName
          

          if let placeOfBirth = passport.placeOfBirth {
            result["placeOfBirth"] = placeOfBirth
          } else {
            result["placeOfBirth"] = ""
          }
          
         
          let rawFiles: NSMutableDictionary = [:]
          
       
          for (id, dataGroup) in passport.dataGroupsRead {
            let fileKey = self.getFileNameForDataGroupId(id)
            if let fileKey = fileKey {
              rawFiles[fileKey] = dataGroup.data
            }
          }
                    
    
          result["rawFiles"] = rawFiles

          if includeImages ?? false {
            if let passportImage = passport.passportImage,
               let imageData = passportImage.jpegData(compressionQuality: 0.8)
            {
              result["photo"] = imageData.base64EncodedString()
            }
          }

          resolve(result)
        } catch {
          reject("ERROR_READ_PASSPORT", "Error reading passport", nil)
        }
      }
    } else {
      reject("ERROR_INVALID_BACK_KEY", "Invalid bac key", nil)
    }
  }
  
  private func getFileNameForDataGroupId(_ id: DataGroupId) -> String? {
    for (key, value) in availableFiles {
      if value == id {
        return key
      }
    }
    return nil
  }

  func handleProgress(percentualProgress: Int) -> String {
    let barWidth = 10
    let completedWidth = Int(Double(barWidth) * Double(percentualProgress) / 100.0)
    let remainingWidth = barWidth - completedWidth

    let completedBar = String(repeating: "🔵", count: completedWidth)
    let remainingBar = String(repeating: "⚪️", count: remainingWidth)

    return "[\(completedBar)\(remainingBar)] \(percentualProgress)%"
  }
}