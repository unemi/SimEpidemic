# SimEpidemic
Individual-based Epidemic Simulator (2020-21)

- As a part of [project](http://www.intlab.soka.ac.jp/~unemi/SimEpidemic1/info/) by Tatsuo Unemi, under cooperation with Saki Nawata and Masaaki Miyashita.
- Supported by Cabinet Secretariat of Japanese Government.

This is an individual-based simulator to help understanding the dynamics of epidemic, spread of infectous disease, mainly targetting SARS-CoV-2.

This repository includes two different versions, macOS application and HTTP server. Both run on macOS 10.14, 10.15, and 11.0. The project file SimEpidemic.xcodeproj is tuned for Intel-based machine, but you can configure it for Apple M1 CPU.

You can find more detail of the project at [http://www.intlab.soka.ac.jp/~unemi/SimEpidemic1/info/](http://www.intlab.soka.ac.jp/~unemi/SimEpidemic1/info/)
and the technical detail in Japanese at  [http://www.intlab.soka.ac.jp/~unemi/SimEpidemic1/info/simepidemic-docs.html](http://www.intlab.soka.ac.jp/~unemi/SimEpidemic1/info/simepidemic-docs.html).

## Subdirectories
- SimEpidemic ... macOS application.
- SimEpidemicSV ... HTTP server's main part.
- Sample ... sample parameter files.
- simepiWorld, simepiBackend ... another version of HTTP server under construction.

&copy; Tatsuo Unemi, 2020-21, All rights reserved.

---
