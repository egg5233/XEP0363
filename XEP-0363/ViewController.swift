//
//  ViewController.swift
//  XEP-0363
//
//  Created by David Chen on 2018/3/12.
//  Copyright © 2018年 wistron. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    var session:URLSession?
    var operationQueue:OperationQueue?
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        self.operationQueue = OperationQueue()
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 5.0
        self.session = URLSession(configuration: sessionConfig, delegate: nil, delegateQueue: self.operationQueue)
        
        let image = UIImage(named: "test.png")!
        let imageData = UIImagePNGRepresentation(image)!
        
        XEP0363.shared().connect(toHost: "yourHost.com", myJID: "user@yourHost.com", password: "123456")
        XEP0363.shared().requestUploadFileAddress(file: imageData, name: "test.png") { (error, urlOfSlot) in
            self.uploadImageToURL(imageData: imageData, url: urlOfSlot!, completionHandler: { (error, response) in
                print("upload complete")
            })
        }

    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    final func uploadImageToURL(imageData:Data , url:String , completionHandler:@escaping ((Error?,HTTPURLResponse?)->())){
        // Method created to prevent upload error caused by:
        // https://github.com/guusdk/httpfileuploadcomponent/blob/master/src/main/java/nl/goodbytes/xmpp/xep0363/Servlet.java
        // line213: if ( req.getContentLength() != slot.getSize() )
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL.init(string: url)!)
        request.httpMethod = "PUT"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData
        let task = self.session?.dataTask(with: request, completionHandler: { [weak self] (data: Data?, response: URLResponse?, error: Error?) -> Void in
            completionHandler(error,response as! HTTPURLResponse)
        })
        task?.resume()
    }
}

