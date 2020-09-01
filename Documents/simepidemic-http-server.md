---
title: "simepidemic HTTP Server版仕様書"
tags: ""
---

# simepidemic HTTP Server版仕様書 ver. 0

このドキュメントは、感染シミュレータ SimEpidemic の HTTP server 版における、起動オプション、クライアントとの間のプロトコル等についての仕様を述べたものである。

1.  パラメータ値の取得
    1.  全パラメータの一括取得
        1.  要求: Method: `GET`, Last component of URI: `getParams`  
            Option: `options=<integer>`  
            option として与える整数の意味  
            	1 ... pretty print ... 入れ子の深さに応じて段つけを行う。  
            	2 ... sorted keys ... 辞書内の要素をキー文字列のアルファベット順に並び替える。  
            	4 ... allow fragments  
            	8 ... without escaping slashes  
            ビットごと論理和を取ることで複数のオプションを同時に設定する。  
            Option: `save=<filename>`  
            このオプションが添えられた場合は、ダウンロード形式で応答する。  
            ex. `GET /getParams?options=3 HTTP/1.1`  
        2.  応答：  
            `Content-type: application/json`  
2.  パラメータ値の設定
    1.  全パラメータ値の一括設定
