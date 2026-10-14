# Lending Club verisiyle bireysel kredi skorkartı

*English: [README.md](README.md)*

Bu projede, bir bankanın bireysel kredi başvurularını değerlendirirken kullandığı
türden bir skorkart kurdum. Model, başvuru anındaki bilgilere bakarak kredinin
batma olasılığını tahmin ediyor ve her başvuruya bir puan veriyor.

Veri, ABD'deki Lending Club platformunun 2007-2018 arasında verdiği 2,2 milyon
kredi.

Verdiğim her kararı ve arkasındaki rakamları [`docs/decisions.md`](docs/decisions.md)
dosyasında tek tek yazdım.

## Kısaca sonuçlar

| Dönem            | Batma oranı | Gini  |
|------------------|-------------|-------|
| 2012-2013 (kurulum) | %12,4    | 0,328 |
| 2014 (ayar)      | %13,7       | 0,323 |
| 2015 (son test)  | %14,9       | 0,336 |

- Model iyiyi kötüden ayırabiliyor ve bu gücünü zamanla kaybetmiyor. Hiç görmediği
  2015 kredilerinde, kurulduğu dönemdeki kadar başarılı.
- Sadece başvuru bilgileriyle, Lending Club'ın kendi risk notu kadar iyi sonuç
  veriyor.
- Başvuranların profili 2014-2018 arasında neredeyse hiç değişmemiş.
- Ama batma oranı artmış. Model 2015 için %13,0 tahmin ediyor, gerçekleşen %14,9.
  Yani aynı profildeki insanlar daha çok batmış. Bu yüzden modelin yeniden
  kurulmasına değil, tahmin seviyesinin güncellenmesine ihtiyaç var.

## Nasıl yaptım

1. Veriyi PostgreSQL'e yükledim ve SQL ile inceledim.
2. Sadece 36 ay vadeli kredileri aldım. 2015'ten sonra verilen kredilerin çoğu
   henüz kapanmadığı için sonuçlarını kullanamadım.
3. Veriyi zamana göre böldüm: Eylül 2012 - 2013 modeli kurmak için, 2014 ayar
   yapmak için, 2015 son test için. Model bitene kadar 2015'e hiç bakmadım.
4. Batan krediyi "zarar yazılan kredi" olarak tanımladım.
5. 60 aday bilgiden 11'ini seçtim, modeli kurdum ve sonucu puana çevirdim.
6. Modeli kaydedip dondurdum, sonra 2015 kredilerinde test ettim.

## Modelin baktığı 11 bilgi

- Kredi notu (FICO)
- Son iki yılda kaç yeni kredi açtığı
- Toplam kredi limiti
- Kredi kartlarındaki boş limit
- Son kredi başvurusundan bu yana geçen süre
- Kredi tutarının gelire oranı
- Kredinin ne için alındığı
- Yıllık gelir
- Borç / gelir oranı
- En eski kredi kartının yaşı
- Kartlarını limitlerine ne kadar yakın kullandığı

Puanı en çok etkileyen iki bilgi kredi notu ve son iki yılda açılan yeni krediler.
Son dönemde art arda kredi çeken müşteri, bankacılıkta da bildiğimiz gibi, genelde
nakit sıkıntısı içindeki müşteridir.

## Dikkat çeken bulgular

- **Geçmiş gecikmeler neredeyse hiç işe yaramıyor.** Bir bankada en güçlü bilgiler
  arasındadır. Sebebi büyük ihtimalle şu: Lending Club kötü geçmişi olanları zaten
  reddetmiş, onaylananlar arasında bu bilgi tükenmiş.
- **Lending Club'ın kuralları veride görünüyor.** Kredi notu 660'ın altında olan,
  kredi geçmişi 3 yıldan kısa olan kimse yok. Kredi tutarı en fazla 35.000 dolar.
- **Gecikme faizi ödeyip krediyi kapatanları "kötü" saysak da sonuç değişmiyor.**

## Bankada nasıl kullanılır

Puanlar 600'lük uluslararası ölçekte, ama Findeks'e benzeyen 1-1900 arası bir
görünümü de var. 2015 kredileri üzerinde, belli bir puanın altını reddetsek ne
olurdu:

- **700'ün altı reddedilirse:** başvuruların %14'ü reddedilir, batacak kredilerin
  %26'sından kurtulunur.
- **800'ün altı reddedilirse:** başvuruların %29'u reddedilir, batacak kredilerin
  %47'sinden kurtulunur.
- **900'ün altı reddedilirse:** başvuruların %47'si reddedilir, batacak kredilerin
  %68'inden kurtulunur.

Hangi eşiğin doğru olduğu, ödeyen müşteriden kazanılan faiz ile batan müşteride
kaybedilen paranın dengesine bağlı.

## Sınırlamalar

- Aylık ödeme geçmişi yok, bir kredinin kaç gün geciktiği görülemiyor.
- Sadece onaylanan krediler var. Reddedilenler kredi alsaydı ne olurdu, bilmiyoruz.
- 2012-2015 ABD ekonomisi için sakin bir dönem. Model hiç kriz görmedi.


## Sonuç

Sadece başvuru bilgileriyle kurulan 11 değişkenli basit bir model, Lending Club'ın
kendi risk notu kadar iyi ayırt ediyor ve bu başarısını zaman içinde koruyor.
Zayıf noktası seviye: 2015'te batma oranı arttı ve model bunu öngöremedi. Pratikte
kullanılacak olsa ilk iş güncel veriyle yeniden kalibre etmek olurdu.

Projedeki asıl iş modelden çok veriyle ilgiliydi: hangi kredilerin sonucunun
gerçekten bilindiği, hangi bilginin hangi tarihten itibaren toplandığı ve
platformun kendi kurallarının veriyi nasıl şekillendirdiği. Bunlar gözden
kaçsaydı model kâğıt üzerinde daha iyi görünür, gerçekte daha kötü çalışırdı.
