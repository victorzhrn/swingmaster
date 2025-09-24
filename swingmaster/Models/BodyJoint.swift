//
//  BodyJoint.swift
//  swingmaster
//
//  App-defined joint enumeration decoupled from Vision and COCO.
//

import Foundation
import CoreGraphics

public enum BodyJoint: String, CaseIterable, Codable, Sendable, Hashable {
    case nose
    case leftEye
    case rightEye
    case leftEar
    case rightEar
    case neck
    case root
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
}


