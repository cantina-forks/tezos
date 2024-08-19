(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2019--2021 Nomadic Labs, <contact@nomadic-labs.com>         *)
(* Copyright (c) 2019 Cryptium Labs <hello@cryptium.ch>                      *)
(*                                                                           *)
(* Permission is hereby granted, free of charge, to any person obtaining a   *)
(* copy of this software and associated documentation files (the "Software"),*)
(* to deal in the Software without restriction, including without limitation *)
(* the rights to use, copy, modify, merge, publish, distribute, sublicense,  *)
(* and/or sell copies of the Software, and to permit persons to whom the     *)
(* Software is furnished to do so, subject to the following conditions:      *)
(*                                                                           *)
(* The above copyright notice and this permission notice shall be included   *)
(* in all copies or substantial portions of the Software.                    *)
(*                                                                           *)
(* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR*)
(* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  *)
(* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL   *)
(* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER*)
(* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING   *)
(* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER       *)
(* DEALINGS IN THE SOFTWARE.                                                 *)
(*                                                                           *)
(*****************************************************************************)

(** The tables are precomputed using this the following formulas:

let max_attestations = 256
let max_reward = 40

let r = 0.5
let a = 3.
let b = 1.5

let ( -- ) i j = List.init (j - i + 1) (fun x -> x + i)

let baking_rewards =
  let reward p e =
    let r_aux =
      if p = 0 then
        r *. (float_of_int max_reward)
      else
        a
    in
    let r = r_aux /. (float_of_int max_attestations) in
    let r = 1_000_000. *. r in
    Float.to_int ((float_of_int e) *. (ceil r)) in

  let ps = 0 -- 2 in
  let es = 0 -- max_attestations in

  List.map (fun p ->
      List.map (fun e ->
          reward p e
        ) es |> Array.of_list
    ) ps |> Array.of_list


let attesting_rewards =
  let reward p e =
    let r_aux =
                (1. -. r) *.
                (float_of_int max_reward) /.
                (float_of_int max_attestations) in
    let r = if p = 0 then r_aux else r_aux /. b in
    let r = 1_000_000. *. r in
    Float.to_int ((float_of_int e) *. (floor r)) in

  let ps = 0 -- 2 in
  let es = 0 -- max_attestations in

  List.map (fun p ->
      List.map (fun e ->
          reward p e
        ) es |> Array.of_list
    ) ps |> Array.of_list

  *)

let baking_rewards : int array array =
  [|
    [|
      0;
      78125;
      156250;
      234375;
      312500;
      390625;
      468750;
      546875;
      625000;
      703125;
      781250;
      859375;
      937500;
      1015625;
      1093750;
      1171875;
      1250000;
      1328125;
      1406250;
      1484375;
      1562500;
      1640625;
      1718750;
      1796875;
      1875000;
      1953125;
      2031250;
      2109375;
      2187500;
      2265625;
      2343750;
      2421875;
      2500000;
      2578125;
      2656250;
      2734375;
      2812500;
      2890625;
      2968750;
      3046875;
      3125000;
      3203125;
      3281250;
      3359375;
      3437500;
      3515625;
      3593750;
      3671875;
      3750000;
      3828125;
      3906250;
      3984375;
      4062500;
      4140625;
      4218750;
      4296875;
      4375000;
      4453125;
      4531250;
      4609375;
      4687500;
      4765625;
      4843750;
      4921875;
      5000000;
      5078125;
      5156250;
      5234375;
      5312500;
      5390625;
      5468750;
      5546875;
      5625000;
      5703125;
      5781250;
      5859375;
      5937500;
      6015625;
      6093750;
      6171875;
      6250000;
      6328125;
      6406250;
      6484375;
      6562500;
      6640625;
      6718750;
      6796875;
      6875000;
      6953125;
      7031250;
      7109375;
      7187500;
      7265625;
      7343750;
      7421875;
      7500000;
      7578125;
      7656250;
      7734375;
      7812500;
      7890625;
      7968750;
      8046875;
      8125000;
      8203125;
      8281250;
      8359375;
      8437500;
      8515625;
      8593750;
      8671875;
      8750000;
      8828125;
      8906250;
      8984375;
      9062500;
      9140625;
      9218750;
      9296875;
      9375000;
      9453125;
      9531250;
      9609375;
      9687500;
      9765625;
      9843750;
      9921875;
      10000000;
      10078125;
      10156250;
      10234375;
      10312500;
      10390625;
      10468750;
      10546875;
      10625000;
      10703125;
      10781250;
      10859375;
      10937500;
      11015625;
      11093750;
      11171875;
      11250000;
      11328125;
      11406250;
      11484375;
      11562500;
      11640625;
      11718750;
      11796875;
      11875000;
      11953125;
      12031250;
      12109375;
      12187500;
      12265625;
      12343750;
      12421875;
      12500000;
      12578125;
      12656250;
      12734375;
      12812500;
      12890625;
      12968750;
      13046875;
      13125000;
      13203125;
      13281250;
      13359375;
      13437500;
      13515625;
      13593750;
      13671875;
      13750000;
      13828125;
      13906250;
      13984375;
      14062500;
      14140625;
      14218750;
      14296875;
      14375000;
      14453125;
      14531250;
      14609375;
      14687500;
      14765625;
      14843750;
      14921875;
      15000000;
      15078125;
      15156250;
      15234375;
      15312500;
      15390625;
      15468750;
      15546875;
      15625000;
      15703125;
      15781250;
      15859375;
      15937500;
      16015625;
      16093750;
      16171875;
      16250000;
      16328125;
      16406250;
      16484375;
      16562500;
      16640625;
      16718750;
      16796875;
      16875000;
      16953125;
      17031250;
      17109375;
      17187500;
      17265625;
      17343750;
      17421875;
      17500000;
      17578125;
      17656250;
      17734375;
      17812500;
      17890625;
      17968750;
      18046875;
      18125000;
      18203125;
      18281250;
      18359375;
      18437500;
      18515625;
      18593750;
      18671875;
      18750000;
      18828125;
      18906250;
      18984375;
      19062500;
      19140625;
      19218750;
      19296875;
      19375000;
      19453125;
      19531250;
      19609375;
      19687500;
      19765625;
      19843750;
      19921875;
      20000000;
    |];
    [|
      0;
      11719;
      23438;
      35157;
      46876;
      58595;
      70314;
      82033;
      93752;
      105471;
      117190;
      128909;
      140628;
      152347;
      164066;
      175785;
      187504;
      199223;
      210942;
      222661;
      234380;
      246099;
      257818;
      269537;
      281256;
      292975;
      304694;
      316413;
      328132;
      339851;
      351570;
      363289;
      375008;
      386727;
      398446;
      410165;
      421884;
      433603;
      445322;
      457041;
      468760;
      480479;
      492198;
      503917;
      515636;
      527355;
      539074;
      550793;
      562512;
      574231;
      585950;
      597669;
      609388;
      621107;
      632826;
      644545;
      656264;
      667983;
      679702;
      691421;
      703140;
      714859;
      726578;
      738297;
      750016;
      761735;
      773454;
      785173;
      796892;
      808611;
      820330;
      832049;
      843768;
      855487;
      867206;
      878925;
      890644;
      902363;
      914082;
      925801;
      937520;
      949239;
      960958;
      972677;
      984396;
      996115;
      1007834;
      1019553;
      1031272;
      1042991;
      1054710;
      1066429;
      1078148;
      1089867;
      1101586;
      1113305;
      1125024;
      1136743;
      1148462;
      1160181;
      1171900;
      1183619;
      1195338;
      1207057;
      1218776;
      1230495;
      1242214;
      1253933;
      1265652;
      1277371;
      1289090;
      1300809;
      1312528;
      1324247;
      1335966;
      1347685;
      1359404;
      1371123;
      1382842;
      1394561;
      1406280;
      1417999;
      1429718;
      1441437;
      1453156;
      1464875;
      1476594;
      1488313;
      1500032;
      1511751;
      1523470;
      1535189;
      1546908;
      1558627;
      1570346;
      1582065;
      1593784;
      1605503;
      1617222;
      1628941;
      1640660;
      1652379;
      1664098;
      1675817;
      1687536;
      1699255;
      1710974;
      1722693;
      1734412;
      1746131;
      1757850;
      1769569;
      1781288;
      1793007;
      1804726;
      1816445;
      1828164;
      1839883;
      1851602;
      1863321;
      1875040;
      1886759;
      1898478;
      1910197;
      1921916;
      1933635;
      1945354;
      1957073;
      1968792;
      1980511;
      1992230;
      2003949;
      2015668;
      2027387;
      2039106;
      2050825;
      2062544;
      2074263;
      2085982;
      2097701;
      2109420;
      2121139;
      2132858;
      2144577;
      2156296;
      2168015;
      2179734;
      2191453;
      2203172;
      2214891;
      2226610;
      2238329;
      2250048;
      2261767;
      2273486;
      2285205;
      2296924;
      2308643;
      2320362;
      2332081;
      2343800;
      2355519;
      2367238;
      2378957;
      2390676;
      2402395;
      2414114;
      2425833;
      2437552;
      2449271;
      2460990;
      2472709;
      2484428;
      2496147;
      2507866;
      2519585;
      2531304;
      2543023;
      2554742;
      2566461;
      2578180;
      2589899;
      2601618;
      2613337;
      2625056;
      2636775;
      2648494;
      2660213;
      2671932;
      2683651;
      2695370;
      2707089;
      2718808;
      2730527;
      2742246;
      2753965;
      2765684;
      2777403;
      2789122;
      2800841;
      2812560;
      2824279;
      2835998;
      2847717;
      2859436;
      2871155;
      2882874;
      2894593;
      2906312;
      2918031;
      2929750;
      2941469;
      2953188;
      2964907;
      2976626;
      2988345;
      3000064;
    |];
    [|
      0;
      11719;
      23438;
      35157;
      46876;
      58595;
      70314;
      82033;
      93752;
      105471;
      117190;
      128909;
      140628;
      152347;
      164066;
      175785;
      187504;
      199223;
      210942;
      222661;
      234380;
      246099;
      257818;
      269537;
      281256;
      292975;
      304694;
      316413;
      328132;
      339851;
      351570;
      363289;
      375008;
      386727;
      398446;
      410165;
      421884;
      433603;
      445322;
      457041;
      468760;
      480479;
      492198;
      503917;
      515636;
      527355;
      539074;
      550793;
      562512;
      574231;
      585950;
      597669;
      609388;
      621107;
      632826;
      644545;
      656264;
      667983;
      679702;
      691421;
      703140;
      714859;
      726578;
      738297;
      750016;
      761735;
      773454;
      785173;
      796892;
      808611;
      820330;
      832049;
      843768;
      855487;
      867206;
      878925;
      890644;
      902363;
      914082;
      925801;
      937520;
      949239;
      960958;
      972677;
      984396;
      996115;
      1007834;
      1019553;
      1031272;
      1042991;
      1054710;
      1066429;
      1078148;
      1089867;
      1101586;
      1113305;
      1125024;
      1136743;
      1148462;
      1160181;
      1171900;
      1183619;
      1195338;
      1207057;
      1218776;
      1230495;
      1242214;
      1253933;
      1265652;
      1277371;
      1289090;
      1300809;
      1312528;
      1324247;
      1335966;
      1347685;
      1359404;
      1371123;
      1382842;
      1394561;
      1406280;
      1417999;
      1429718;
      1441437;
      1453156;
      1464875;
      1476594;
      1488313;
      1500032;
      1511751;
      1523470;
      1535189;
      1546908;
      1558627;
      1570346;
      1582065;
      1593784;
      1605503;
      1617222;
      1628941;
      1640660;
      1652379;
      1664098;
      1675817;
      1687536;
      1699255;
      1710974;
      1722693;
      1734412;
      1746131;
      1757850;
      1769569;
      1781288;
      1793007;
      1804726;
      1816445;
      1828164;
      1839883;
      1851602;
      1863321;
      1875040;
      1886759;
      1898478;
      1910197;
      1921916;
      1933635;
      1945354;
      1957073;
      1968792;
      1980511;
      1992230;
      2003949;
      2015668;
      2027387;
      2039106;
      2050825;
      2062544;
      2074263;
      2085982;
      2097701;
      2109420;
      2121139;
      2132858;
      2144577;
      2156296;
      2168015;
      2179734;
      2191453;
      2203172;
      2214891;
      2226610;
      2238329;
      2250048;
      2261767;
      2273486;
      2285205;
      2296924;
      2308643;
      2320362;
      2332081;
      2343800;
      2355519;
      2367238;
      2378957;
      2390676;
      2402395;
      2414114;
      2425833;
      2437552;
      2449271;
      2460990;
      2472709;
      2484428;
      2496147;
      2507866;
      2519585;
      2531304;
      2543023;
      2554742;
      2566461;
      2578180;
      2589899;
      2601618;
      2613337;
      2625056;
      2636775;
      2648494;
      2660213;
      2671932;
      2683651;
      2695370;
      2707089;
      2718808;
      2730527;
      2742246;
      2753965;
      2765684;
      2777403;
      2789122;
      2800841;
      2812560;
      2824279;
      2835998;
      2847717;
      2859436;
      2871155;
      2882874;
      2894593;
      2906312;
      2918031;
      2929750;
      2941469;
      2953188;
      2964907;
      2976626;
      2988345;
      3000064;
    |];
  |]

let attesting_rewards : int array array =
  [|
    [|
      0;
      78125;
      156250;
      234375;
      312500;
      390625;
      468750;
      546875;
      625000;
      703125;
      781250;
      859375;
      937500;
      1015625;
      1093750;
      1171875;
      1250000;
      1328125;
      1406250;
      1484375;
      1562500;
      1640625;
      1718750;
      1796875;
      1875000;
      1953125;
      2031250;
      2109375;
      2187500;
      2265625;
      2343750;
      2421875;
      2500000;
      2578125;
      2656250;
      2734375;
      2812500;
      2890625;
      2968750;
      3046875;
      3125000;
      3203125;
      3281250;
      3359375;
      3437500;
      3515625;
      3593750;
      3671875;
      3750000;
      3828125;
      3906250;
      3984375;
      4062500;
      4140625;
      4218750;
      4296875;
      4375000;
      4453125;
      4531250;
      4609375;
      4687500;
      4765625;
      4843750;
      4921875;
      5000000;
      5078125;
      5156250;
      5234375;
      5312500;
      5390625;
      5468750;
      5546875;
      5625000;
      5703125;
      5781250;
      5859375;
      5937500;
      6015625;
      6093750;
      6171875;
      6250000;
      6328125;
      6406250;
      6484375;
      6562500;
      6640625;
      6718750;
      6796875;
      6875000;
      6953125;
      7031250;
      7109375;
      7187500;
      7265625;
      7343750;
      7421875;
      7500000;
      7578125;
      7656250;
      7734375;
      7812500;
      7890625;
      7968750;
      8046875;
      8125000;
      8203125;
      8281250;
      8359375;
      8437500;
      8515625;
      8593750;
      8671875;
      8750000;
      8828125;
      8906250;
      8984375;
      9062500;
      9140625;
      9218750;
      9296875;
      9375000;
      9453125;
      9531250;
      9609375;
      9687500;
      9765625;
      9843750;
      9921875;
      10000000;
      10078125;
      10156250;
      10234375;
      10312500;
      10390625;
      10468750;
      10546875;
      10625000;
      10703125;
      10781250;
      10859375;
      10937500;
      11015625;
      11093750;
      11171875;
      11250000;
      11328125;
      11406250;
      11484375;
      11562500;
      11640625;
      11718750;
      11796875;
      11875000;
      11953125;
      12031250;
      12109375;
      12187500;
      12265625;
      12343750;
      12421875;
      12500000;
      12578125;
      12656250;
      12734375;
      12812500;
      12890625;
      12968750;
      13046875;
      13125000;
      13203125;
      13281250;
      13359375;
      13437500;
      13515625;
      13593750;
      13671875;
      13750000;
      13828125;
      13906250;
      13984375;
      14062500;
      14140625;
      14218750;
      14296875;
      14375000;
      14453125;
      14531250;
      14609375;
      14687500;
      14765625;
      14843750;
      14921875;
      15000000;
      15078125;
      15156250;
      15234375;
      15312500;
      15390625;
      15468750;
      15546875;
      15625000;
      15703125;
      15781250;
      15859375;
      15937500;
      16015625;
      16093750;
      16171875;
      16250000;
      16328125;
      16406250;
      16484375;
      16562500;
      16640625;
      16718750;
      16796875;
      16875000;
      16953125;
      17031250;
      17109375;
      17187500;
      17265625;
      17343750;
      17421875;
      17500000;
      17578125;
      17656250;
      17734375;
      17812500;
      17890625;
      17968750;
      18046875;
      18125000;
      18203125;
      18281250;
      18359375;
      18437500;
      18515625;
      18593750;
      18671875;
      18750000;
      18828125;
      18906250;
      18984375;
      19062500;
      19140625;
      19218750;
      19296875;
      19375000;
      19453125;
      19531250;
      19609375;
      19687500;
      19765625;
      19843750;
      19921875;
      20000000;
    |];
    [|
      0;
      52083;
      104166;
      156249;
      208332;
      260415;
      312498;
      364581;
      416664;
      468747;
      520830;
      572913;
      624996;
      677079;
      729162;
      781245;
      833328;
      885411;
      937494;
      989577;
      1041660;
      1093743;
      1145826;
      1197909;
      1249992;
      1302075;
      1354158;
      1406241;
      1458324;
      1510407;
      1562490;
      1614573;
      1666656;
      1718739;
      1770822;
      1822905;
      1874988;
      1927071;
      1979154;
      2031237;
      2083320;
      2135403;
      2187486;
      2239569;
      2291652;
      2343735;
      2395818;
      2447901;
      2499984;
      2552067;
      2604150;
      2656233;
      2708316;
      2760399;
      2812482;
      2864565;
      2916648;
      2968731;
      3020814;
      3072897;
      3124980;
      3177063;
      3229146;
      3281229;
      3333312;
      3385395;
      3437478;
      3489561;
      3541644;
      3593727;
      3645810;
      3697893;
      3749976;
      3802059;
      3854142;
      3906225;
      3958308;
      4010391;
      4062474;
      4114557;
      4166640;
      4218723;
      4270806;
      4322889;
      4374972;
      4427055;
      4479138;
      4531221;
      4583304;
      4635387;
      4687470;
      4739553;
      4791636;
      4843719;
      4895802;
      4947885;
      4999968;
      5052051;
      5104134;
      5156217;
      5208300;
      5260383;
      5312466;
      5364549;
      5416632;
      5468715;
      5520798;
      5572881;
      5624964;
      5677047;
      5729130;
      5781213;
      5833296;
      5885379;
      5937462;
      5989545;
      6041628;
      6093711;
      6145794;
      6197877;
      6249960;
      6302043;
      6354126;
      6406209;
      6458292;
      6510375;
      6562458;
      6614541;
      6666624;
      6718707;
      6770790;
      6822873;
      6874956;
      6927039;
      6979122;
      7031205;
      7083288;
      7135371;
      7187454;
      7239537;
      7291620;
      7343703;
      7395786;
      7447869;
      7499952;
      7552035;
      7604118;
      7656201;
      7708284;
      7760367;
      7812450;
      7864533;
      7916616;
      7968699;
      8020782;
      8072865;
      8124948;
      8177031;
      8229114;
      8281197;
      8333280;
      8385363;
      8437446;
      8489529;
      8541612;
      8593695;
      8645778;
      8697861;
      8749944;
      8802027;
      8854110;
      8906193;
      8958276;
      9010359;
      9062442;
      9114525;
      9166608;
      9218691;
      9270774;
      9322857;
      9374940;
      9427023;
      9479106;
      9531189;
      9583272;
      9635355;
      9687438;
      9739521;
      9791604;
      9843687;
      9895770;
      9947853;
      9999936;
      10052019;
      10104102;
      10156185;
      10208268;
      10260351;
      10312434;
      10364517;
      10416600;
      10468683;
      10520766;
      10572849;
      10624932;
      10677015;
      10729098;
      10781181;
      10833264;
      10885347;
      10937430;
      10989513;
      11041596;
      11093679;
      11145762;
      11197845;
      11249928;
      11302011;
      11354094;
      11406177;
      11458260;
      11510343;
      11562426;
      11614509;
      11666592;
      11718675;
      11770758;
      11822841;
      11874924;
      11927007;
      11979090;
      12031173;
      12083256;
      12135339;
      12187422;
      12239505;
      12291588;
      12343671;
      12395754;
      12447837;
      12499920;
      12552003;
      12604086;
      12656169;
      12708252;
      12760335;
      12812418;
      12864501;
      12916584;
      12968667;
      13020750;
      13072833;
      13124916;
      13176999;
      13229082;
      13281165;
      13333248;
    |];
    [|
      0;
      52083;
      104166;
      156249;
      208332;
      260415;
      312498;
      364581;
      416664;
      468747;
      520830;
      572913;
      624996;
      677079;
      729162;
      781245;
      833328;
      885411;
      937494;
      989577;
      1041660;
      1093743;
      1145826;
      1197909;
      1249992;
      1302075;
      1354158;
      1406241;
      1458324;
      1510407;
      1562490;
      1614573;
      1666656;
      1718739;
      1770822;
      1822905;
      1874988;
      1927071;
      1979154;
      2031237;
      2083320;
      2135403;
      2187486;
      2239569;
      2291652;
      2343735;
      2395818;
      2447901;
      2499984;
      2552067;
      2604150;
      2656233;
      2708316;
      2760399;
      2812482;
      2864565;
      2916648;
      2968731;
      3020814;
      3072897;
      3124980;
      3177063;
      3229146;
      3281229;
      3333312;
      3385395;
      3437478;
      3489561;
      3541644;
      3593727;
      3645810;
      3697893;
      3749976;
      3802059;
      3854142;
      3906225;
      3958308;
      4010391;
      4062474;
      4114557;
      4166640;
      4218723;
      4270806;
      4322889;
      4374972;
      4427055;
      4479138;
      4531221;
      4583304;
      4635387;
      4687470;
      4739553;
      4791636;
      4843719;
      4895802;
      4947885;
      4999968;
      5052051;
      5104134;
      5156217;
      5208300;
      5260383;
      5312466;
      5364549;
      5416632;
      5468715;
      5520798;
      5572881;
      5624964;
      5677047;
      5729130;
      5781213;
      5833296;
      5885379;
      5937462;
      5989545;
      6041628;
      6093711;
      6145794;
      6197877;
      6249960;
      6302043;
      6354126;
      6406209;
      6458292;
      6510375;
      6562458;
      6614541;
      6666624;
      6718707;
      6770790;
      6822873;
      6874956;
      6927039;
      6979122;
      7031205;
      7083288;
      7135371;
      7187454;
      7239537;
      7291620;
      7343703;
      7395786;
      7447869;
      7499952;
      7552035;
      7604118;
      7656201;
      7708284;
      7760367;
      7812450;
      7864533;
      7916616;
      7968699;
      8020782;
      8072865;
      8124948;
      8177031;
      8229114;
      8281197;
      8333280;
      8385363;
      8437446;
      8489529;
      8541612;
      8593695;
      8645778;
      8697861;
      8749944;
      8802027;
      8854110;
      8906193;
      8958276;
      9010359;
      9062442;
      9114525;
      9166608;
      9218691;
      9270774;
      9322857;
      9374940;
      9427023;
      9479106;
      9531189;
      9583272;
      9635355;
      9687438;
      9739521;
      9791604;
      9843687;
      9895770;
      9947853;
      9999936;
      10052019;
      10104102;
      10156185;
      10208268;
      10260351;
      10312434;
      10364517;
      10416600;
      10468683;
      10520766;
      10572849;
      10624932;
      10677015;
      10729098;
      10781181;
      10833264;
      10885347;
      10937430;
      10989513;
      11041596;
      11093679;
      11145762;
      11197845;
      11249928;
      11302011;
      11354094;
      11406177;
      11458260;
      11510343;
      11562426;
      11614509;
      11666592;
      11718675;
      11770758;
      11822841;
      11874924;
      11927007;
      11979090;
      12031173;
      12083256;
      12135339;
      12187422;
      12239505;
      12291588;
      12343671;
      12395754;
      12447837;
      12499920;
      12552003;
      12604086;
      12656169;
      12708252;
      12760335;
      12812418;
      12864501;
      12916584;
      12968667;
      13020750;
      13072833;
      13124916;
      13176999;
      13229082;
      13281165;
      13333248;
    |];
  |]
