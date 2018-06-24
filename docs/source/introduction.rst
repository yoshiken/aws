.. _Introduction:

************
Introduction
************

`AWS` とは *Ada Web Server* の略称で、HTTP1.1プロトコルをAdaで実装しています。(RFC-2616に準拠)

ゴールは完全なWeb serverの構築ではなく、webブラウザ(Internet Explorer や Netscape Navigator など)をしようしてAdaアプリケーションをコントロールすることです。
後述するように、2つのAdaアプリケーションが `HTTP` プロトコルを介して情報を交換することが可能です。
これはクライアント側も `AWS` でHTTPプロトコルを実装しているからです。

さらにこのライブラリによって1つのアプリケーションに複数のサーバーを持つことができます。
これはサービスによって異なる `HTTP` のポートを使用することができるからです。また、サービスの優先度によって異なるポートを持つことが可能です。
例えば、特定のポートは優先度が高いサービスを割り当てるなどが可能です。

設計として、標準のCGIサーバーとの大きな違いは `AWS` には1つの実行ファイルしかありません。
標準のCGIサーバーはリクエストごとに1つの実行ファイルを持ちますが、ビルドする際やプロジェクトが大きくなっていき配布する時に苦労してしまうからです。
`AWS` がセッションデータを容易に扱えることが簡単だということもみればわかります。

`AWS` は `SSL` を用いた `HTTPS` (secure 'HTTP')もサポートしています。
これは `OpenSSL` と `GNUTLS` を用いたオープンソースSSLに基づいています。

主なサポート機能 :

* HTTP

* HTTS (Secure HTTP) SSLv3

* テンプレートWebページ(コードとデザインの分離)

* Web Services (SOAP)

* WSDL (WSDLドキュメントからstub/skeletonを生成できます)

* BASIC認証とDigest認証

* Transparent session handling(serverサイド)

* HTTP state management(クライアントサイド)

* ファイルアップロード

* Server push

* SMTP / POP (client API)

* LDAP (client API)

* Embedded resources (webサーバー依存)

* HTTPSを含むクライアントAPI

* webサーバーのアクティビティログ
