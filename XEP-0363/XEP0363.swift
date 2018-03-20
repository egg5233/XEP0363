//  Created by David on 2018/3/8.
//  Copyright © 2018年  All rights reserved.
// https://xmpp.org/extensions/xep-0363.html

import Foundation
import XMPPFramework

class XEP0363:NSObject {
    
    private var isStreamConnected:Bool=false
    private var isStreamConnecting:Bool=false
    private var stream:XMPPStream!
    private var password:String?
    private var MCU:XMPPMUC?
    private var supportsHttpUpload:Bool=false
    private var maxFileSize:Double=0
    private var uploadIdentifier:String?
    private var form:String?
    private var tasks:[String:((Error?,String?) -> Void)] = [String:((Error?,String?) -> Void)]()
    private static var instance:XEP0363?

    override init() {
        super.init()
    }
    
    @discardableResult static func shared() -> XEP0363 {
        if (instance == nil){
            instance=XEP0363.init()
        }
        return instance!
    }
    
    //Stream
    func connect(toHost hostname:String, myJID:String , password:String){
        stream = XMPPStream()
        stream.startTLSPolicy = XMPPStreamStartTLSPolicy.required
        stream.addDelegate(self, delegateQueue: DispatchQueue.main)
        stream.hostName = hostname
        //XEP-0363 requires TLS to work
        stream.hostPort = 5222
        stream.myJID = XMPPJID(string: myJID)
        self.password = password
        do {
            try stream.connect(withTimeout: 30)
        }
        catch {
            print("error occured in connecting")
        }
    }
    
    func disconnect(){
        stream.send(XMPPPresence(type: "unavailable"))
        stream.disconnect()
    }
    
    func requestUploadFileAddress(file:Data , name:String , block:@escaping ((Error?,String?) -> Void)) {
        if (isStreamConnected == false || isStreamConnecting == true){
            DispatchQueue.main.asyncAfter(deadline: .now()+3, execute: {
                self.requestUploadFileAddress(file: file, name: name, block: block)
            })
            return
        }

        //also make this task-id
        let id = NSUUID().uuidString
        if (supportsHttpUpload == false) {
            let error = NSError.init(domain: "", code: -99, userInfo: ["info":"remote does not support httpupload"])
            block(error, nil)
            return
        }
        
        if (uploadIdentifier == nil || form == nil) {
            let error = NSError.init(domain: "", code: -99, userInfo: ["info":"uploadIdentifier and forms are nil"])
            block(error, nil)
            return
        }
        //store the block , excute it later
        tasks[id] = block
        sendSlotRequest(id: id, fileSize: String(file.count), name: name, contentType:"image/\(file.extensionType)" )
    }
    
    fileprivate func discoverService(){
        MCU = XMPPMUC.init(dispatchQueue: DispatchQueue.main)
        MCU?.activate(self.stream)
        MCU?.addDelegate(self, delegateQueue: DispatchQueue.main)
        MCU?.discoverServices()
    }
    
    fileprivate func sendFileServiceDiscoveryRequest(){
        let query = DDXMLElement(name: "query", xmlns: "http://jabber.org/protocol/disco#info")
        let iq = XMPPIQ(iqType: .get,
                        to: XMPPJID(string: uploadIdentifier!),
                        elementID: NSUUID().uuidString,
                        child: query)
        self.stream?.send(iq)
    }
    
    fileprivate func sendSlotRequest(id:String , fileSize:String , name:String , contentType:String){
        let query = DDXMLElement(name: "request", xmlns: form!)
        
        let fileNameElement = DDXMLElement.element(withName: "filename") as! DDXMLElement
        fileNameElement.stringValue = name
        
        let sizeElement = DDXMLElement.element(withName: "size") as! DDXMLElement
        sizeElement.stringValue = fileSize
        
        let contentElement = DDXMLElement.element(withName: "content-type") as! DDXMLElement
        contentElement.stringValue = contentType
        
        query.addChild(fileNameElement)
        query.addChild(sizeElement)
        query.addChild(contentElement)
        
        let iq = XMPPIQ(iqType: .get,
                        to: XMPPJID(string: uploadIdentifier!),
                        elementID: id,
                        child: query)
        self.stream?.send(iq)
    }
}

extension XEP0363:XMPPStreamDelegate {

    
    func xmppStream(_ sender: XMPPStream, willSecureWithSettings settings: NSMutableDictionary) {
        settings[GCDAsyncSocketManuallyEvaluateTrust] = NSNumber(booleanLiteral: true)
    }
    
    func xmppStream(_ sender: XMPPStream, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true);
    }
    
    func xmppStreamWillConnect(_ sender: XMPPStream) {
        print("xmppStreamWillConnect")
        self.isStreamConnecting = true
    }
    
    func xmppStreamConnectDidTimeout(_ sender: XMPPStream) {
        print("xmppStreamConnectDidTimeout")
        self.isStreamConnected = false
        self.isStreamConnecting = false
    }
    
    func xmppStreamDidConnect(_ sender: XMPPStream) {
        print("xmppStreamDidConnect")
        self.isStreamConnected = true
        self.isStreamConnecting = false
        do {
            try sender.authenticate(withPassword: self.password!)
        } catch {
            print(error)
        }
    }
    
    func xmppStreamDidAuthenticate(_ sender: XMPPStream) {
        print("xmppStreamDidAuthenticate")
        //Send presence (online-notice)
        stream.send(XMPPPresence())
        self.discoverService()
    }
    
    func xmppStream(_ sender: XMPPStream, didNotAuthenticate error: DDXMLElement) {
        print("didNotAuthenticate:\(error)")
    }
    
    func xmppStream(_ sender: XMPPStream, didFailToSend iq: XMPPIQ, error: Error) {
        if let task = tasks[iq.elementID!] {
            task(error,nil)
            tasks.removeValue(forKey: iq.elementID!)
        }
    }
    
    func xmppStream(_ sender: XMPPStream, didSend iq: XMPPIQ) {
        
    }
    
    /*
     process XEP0363 iq here
     */
    func xmppStream(_ sender: XMPPStream, didReceive iq: XMPPIQ) -> Bool {
        if iq.isResultIQ {
            if uploadIdentifier != nil && iq.attributeStringValue(forName: "from") ==  uploadIdentifier! {
                if let query = iq.element(forName: "query", xmlns: "http://jabber.org/protocol/disco#info") {
                    let x = query.element(forName: "x", xmlns: "jabber:x:data")
                    let fields = x?.elements(forName: "field")
                    for (_,obj) in (fields?.enumerated())! {
                        
                        if (obj.attributeStringValue(forName: "var") == "FORM_TYPE") {
                            form = obj.children?.first?.children?.first?.stringValue
                        }
                        
                        if (obj.attributeStringValue(forName: "var") == "max-file-size") {
                            maxFileSize = Double(obj.children?.first?.children?.first?.stringValue ?? "0")!
                        }
                    }
                }
                
                if let slot =  iq.element(forName: "slot", xmlns: form!) {
                    let put = slot.elements(forName: "put").first
                    let putURL = put?.attributeStringValue(forName: "url")
                    
                    if let task = tasks[iq.elementID!] {
                        task(nil,putURL)
                        tasks.removeValue(forKey: iq.elementID!)
                    } else {
                        print("could not find a task asscociated with id")
                    }
                }
            }
        }
        return true
    }
}

//Discover service
extension XEP0363:XMPPMUCDelegate {
    func xmppMUC(_ sender: XMPPMUC, didDiscoverServices services: [DDXMLElement]) {
        print("didDiscoverServices")
        for (_,obj) in services.enumerated() {
            if ((obj.attributeStringValue(forName: "jid"))?.contains("httpfileupload"))!{
                uploadIdentifier = obj.attributeStringValue(forName: "jid")
                supportsHttpUpload = true
                self.sendFileServiceDiscoveryRequest()
            }
        }
    }
}

extension Data {
    var extensionType: String {
        let array = [UInt8](self)
        let ext: String
        switch (array[0]) {
        case 0xFF:
            ext = "jpg"
        case 0x89:
            ext = "png"
        case 0x47:
            ext = "gif"
        case 0x49, 0x4D :
            ext = "tiff"
        default:
            ext = "unknown"
        }
        return ext
    }
}
