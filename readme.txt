
                            A W S - Ada Web Server
                                19.0 release

Authors:
   Dmitriy Anisimkov
   Pascal Obry


AWSはAda Web Serverの略です。これはあらゆるアプリケーションに組み込むことができる、
小さいがパワフルなHTTP componentです。つまり、Webサーバーを立てること無く、標準の
webサーバーを使用してアプリケーションと通信できるということを意味しています。
AWSはAda with GNATで開発されました。

AWSはSOAP/WSDL, Server Push, HTTPS/SSL, client HTTP, hotplug , modules等様々な
サポートをしています。

AWSはSOAP/WSDLがサポートされており、2つのツールが提供されています。

  ada2wsdl    Adaの言語仕様からWSDLドキュメントを生成します。

  wsdl2aws    WSDLドキュメントからAdaのstub及びSkeletonを生成します

どちらのツールも標準Adaのenumerations,character,records,arraysといった型に対応しています

SOAP実装はhttp://validator.soapware.org/で検証されています。
現在、オンラインサービスとして利用できませんが、実装はApache/AXIS SOAPとして検証されており
相互運用は保証されています。
一部のユーザーは、AWS/SOAP,.NET,gSOAPにおいて問題なく機能したという報告をしています。


上位互換性が無い変更
----------------

以下に示す変更点は、上位互換により導入できない事に留意してください
このようなケースの場合には、適切なコードのアドバイスを行います。もちろんこのような実装
を避けようとはしますが、危険を孕むような実装をするのではなく、キレイなAPIを保つことを主とします。


廃止予定
-------

それぞれの新しいバージョンでは、以前のバージョンと上位互換性を保ちます。
互換性を保つこと自体は本当に重要ですが、APIの「再設計」が長期的には良いと思われる場合もあります。
廃止予定化したすべての機能がこのセクションにリストされます。
これらの機能は、次のバージョンでは削除されます。
GNATの -gnatwj オプションを使用すると、アプリケーションですべての廃止予定機能を
pragmaでタグ付けしたリストを表示できます

ポイント
------

AWS Home Page (PostscriptとPDFでソースと出力可能なドキュメント):
   http://libre.adacore.com/tools/aws

Templates_Parser sources:
  Templates_Parser module (ソースコードとドキュメント) にはAWSが付属されて提供しています。

GNU/Ada - GNAT
  少なくとも、GNAT 2015 GPL EditionもしくはGNAT Pro 7.2が必要です

XML/Ada (オプション):
  このライブラリは、AWS SOAP機能を使用する場合のみに必要です。
  XML/Ada version 2.2.0.以上が必要です。

  http://libre.adacore.com/

OpenSSL(オプション）：
  開発ライブラリを手動でインストールする必要があります。

LibreSSL (オプション）：
  開発ライブラリを手動でインストールする必要があります（> = 2.4.4）。
  LibreSSLはOpenSSLと完全に互換性のある実装です。
  OpenSSLのようにAWSを設定するだけです。

GNUTLS (オプション)
  開発ライブラリを手動でインストールする必要があります。
  GNUTLSのバージョンが3.2.4以上必要です。

OpenSSL (オプション):
    UNIXまたはWin32のソース：
       http://www.openldap.org/
    Win32：
       AWSバインディングはMicrosoft LDAPに動的ライブラリとして使用されます。

Windows Services API (オプション):
Windows NT/2000サービスとしてrunmeデモを構築するには、SETI@Homeプロジェクトの
Ted Dennisonが作成したサービスAPIをダウンロードする必要があります。

http://www.telepath.com/~dennison/Ted/SETI/SETI_Service.html


バグを報告
---------

AdaCoreにバグを報告できます: report@adacore.com


Contributors
------------

Thanks to the contributors and peoples who send feedbacks, ideas
about AWS. In the early stage of the project this is very valuable.

So thanks goes to Georg Bauhaus, Ted Dennison, Wiljan Derks, Sune Falck,
David C. Hoos, Audran Le Baron, Thierry Lelegard, Nicolas Lesbats,
Olivier Ramonat, Jean-Fran�ois Rameau, Maxim Reznik, Jean-Pierre Rosen,
Jerme Roussel, Ariane Sinibardy, Henrik Sundberg.
