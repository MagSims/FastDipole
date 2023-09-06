@testitem "Kitchen Sink" begin
    cryst = Sunny.pyrochlore_primitive_crystal()
    infos = [SpinInfo(1, S=5/2, g=7.2)]
    sys = System(cryst, (1, 1, 1), infos, :SUN; seed=0)

    A,B,C,D = 2.6, -1.3, 0.2, -5.7
    set_exchange!(sys, [A C -D; C A D; D -D B], Bond(1, 2, [0, 0, 0]))

    A,B,C,D,E,F,G,H,K = 2.6, -1.3, 0.2, -5.7, 8.2, 0.3, 2.5, -0.6, 1.3
    set_exchange!(sys, [A F+K E-H; F-K B D+G; E+H D-G C], Bond(1, 4, [1, 0, 0]))#; biquad = -0.2)

    A,B,C,D = 2.6, -1.3, 0.2, -5.7
    set_exchange!(sys, [A D D; D B C; D C B], Bond(4, 4, [1, 1, 0]))#; biquad = 0.3)

    O = stevens_operators(sys, 3)
    c1,c2,c3 = 2.6, -1.3, 0.2, -5.7
    set_onsite_coupling!(sys, c1 * (O[2,-2] - 2O[2,-1] - 2O[2,1]) + c2 * (-7O[4,-3] + 2O[4,-2]+O[4,-1]+O[4,1]+7O[4,3]) + c3 * (O[4,0]+5O[4,4]), 3)

    A = [1 3 1; -1 1 0; 0 0 1]
    sys = reshape_supercell(sys, A)

    # To obtain ground_state (and other golden values) after changing sys:
    #
    #   minimize_energy!(sys)
    #   print(repr(sys.coherents))

    ground_state = [[0.45214062359072044 + 0.06944348150493522im, 0.5863708532087999 + 0.1663131005619199im, 0.3100432449111114 + 0.351300508400207im, 0.03537528798325074 + 0.3900629995653463im, -0.13627268071278648 + 0.14496570032599876im, -0.0299133513970556 - 0.07639445363116497im];;;; [-0.02635759959001974 - 0.06404319084686681im, 0.24705766763090592 - 0.2085076799220013im, -0.4441208331992594 + 0.3066892559047205im, 0.5014865196917019 - 0.1223078788349471im, -0.47806827180940087 - 0.011733814216152426im, 0.319540352558256 - 0.04634922094047352im];;;; [-0.07818730887419299 - 0.4507108666826247im, -0.029117370762171566 - 0.6088045693214829im, 0.23425018139965947 - 0.4057902332964516im, 0.3584799504733425 - 0.15777414155356598im, 0.18082054683455467 + 0.08300137122155007im, -0.06288776006106951 + 0.0526882413047805im];;;; [-0.06070725419221679 + 0.033329906108154964im, -0.23473923381919415 - 0.22228458299023374im, 0.35426848111050574 + 0.40717988343633466im, -0.17742779214457244 - 0.48473428312943007im, 0.04161136048789692 + 0.47639841474148625im, -0.08166757715717216 - 0.3123854894511737im];;;; [-0.781821418320387 + 0.33153005873003394im, 0.18394472969756057 - 0.45292449749619373im, 0.05803346954218823 + 0.13812843375514855im, 0.12122745039156632 + 0.0489355842380238im, -0.007034744223716246 + 0.002919993486734581im, -0.006222903567673034 + 0.015230021316185626im];;;; [0.05711259253999181 - 0.004762568742530607im, -0.02313974269430587 - 0.013160904017533627im, -0.10063638040572893 + 0.009009961138645729im, -0.2470426657520716 - 0.2567611220832205im, -0.630650853914652 - 0.19255553288124444im, -0.6165934825110042 + 0.2094181085486585im];;;; [-0.6945052218787734 - 0.4886915251577914im, 0.48174033408135447 - 0.08308137301521956im, -0.08662474411875379 + 0.12224361540029625im, 0.0224902616205401 + 0.12878266290630117im, -0.006195524410653101 - 0.004430515267950971im, -0.01621883657854597 + 0.0027617780795955267im];;;; [0.039689379744548677 + 0.04134348103132442im, -0.004363605366904462 - 0.026260541389444975im, -0.07041529054175265 - 0.07246066045350816im, 0.043678244639521274 - 0.35362206304117527im, -0.247918040132824 - 0.6110112749930096im, -0.5511696766081456 - 0.34677868221951663im];;;; [0.3469627460303239 + 0.14931798333587631im, -0.2156242976570228 + 0.5113279591124983im, -0.3857482701658712 - 0.35958016213085814im, 0.4342979862959435 - 0.15308088233852174im, -0.023778499691015295 + 0.23990813225744892im, 0.02569416833113292 - 0.02100560830009759im];;;; [0.061328177264115026 + 0.08179048031685549im, 0.09605870962161454 + 0.21910825481736096im, 0.3607946773751248 + 0.20301081302926466im, 0.48691536453432294 - 0.1803540393310634im, 0.22789013944850908 - 0.5542224407481126im, -0.28234202306767187 - 0.22912808721645594im];;;; [-0.2053448778816606 + 0.3170370457993336im, -0.4679678962215671 - 0.2982552055181157im, 0.4191332556442897 - 0.3200420830860253im, 0.07814435848737171 + 0.4538082818475725im, -0.23253177773997522 - 0.0636419775830062im, 0.016403232438055988 + 0.028850646994925202im];;;; [0.10062410602294389 + 0.018044868623814644im, 0.21963461264808445 + 0.09484903767417456im, 0.40237272775963734 - 0.09737749935533652im, 0.23334967901145323 - 0.4638556661600751im, -0.21101616172023493 - 0.5608641626851553im, -0.3627699256902438 + 0.024792727899340308im];;;; [0.05866233567146968 - 0.5820874126672679im, 0.44216519698824763 - 0.35504987748618855im, 0.5098075454923101 + 0.06293751811530868im, 0.15756881397717343 + 0.2127817609999913im, -0.008602173334523908 + 0.023971881808344656im, 0.02968071433283379 - 0.025768790631760647im];;;; [0.5821102583628199 - 0.058435201025780245im, 0.4359949321775104 + 0.3626001876036782im, 0.039851147465032634 + 0.5121296229199577im, -0.17713978388138404 + 0.19678797198470416im, -0.025204822830699587 - 0.003655873299849043im, 0.03116352102530959 + 0.02395433846160244im];;;; [0.5613758844150178 + 0.16469408615841546im, 0.2676924503032746 + 0.4999112210988483im, -0.1556058324999203 + 0.48954232658245084im, -0.23812685224688218 + 0.11575668961062088im, -0.021981413137017642 - 0.012863358036049351im, 0.01987184322324392 + 0.03391290640545071im];;;; [-0.33738568825646986 + 0.47795179985102815im, -0.5596175479248192 + 0.0916442959462655im, -0.4129170777269615 - 0.3055558075799833im, -0.03252986925816942 - 0.2627657065868674im, 0.01928065373550379 - 0.016640459579653582im, -0.038516944507789634 + 0.00783711425282178im]]

    for j = 1:16
        sys.coherents[1,1,1,j] = ground_state[:,1,1,j]
    end

    # Test that this is a local minimum of energy
    minimize_energy!(sys)
    @test isapprox(ground_state[:,1,1,1],sys.coherents[1,1,1,1];atol = 1e-12)
    @test isapprox(ground_state[:,1,1,2],sys.coherents[1,1,1,2];atol = 1e-12)
    @test isapprox(ground_state[:,1,1,3],sys.coherents[1,1,1,3];atol = 1e-12)
    @test isapprox(ground_state[:,1,1,4],sys.coherents[1,1,1,4];atol = 1e-12)

    for j = 1:16
        sys.coherents[1,1,1,j] = ground_state[:,1,1,j]
    end

    # Test energies at arbitrary wave vectors
    ks = [[0.24331089495721447, 0.2818361515716459, 0.21954858411037714],[0.18786753153567903, 0.09763312505570143, 0.19017209963665904],[0.6495802672357117, 0.4232687254439188, 0.3224056821009953]]
    swt = SpinWaveTheory(sys)

    formula = intensity_formula(swt,:perp,kernel = delta_function_kernel)
    disps, is = intensities_bands(swt,ks,formula)

    disps_golden = [1394.4400925881228 1393.7280099644597 1393.0085512630778 1392.9195249813647 1279.2399190769481 1279.0945684836706 1278.2245185268516 1277.6917614912365 1194.366336265456 1193.750083634245 1191.5835196713772 1189.7944513506748 1131.4224395981914 1131.2027700848616 1065.2429278600928 1065.0958924560794 1026.649340932247 1024.0283485696764 1022.8304063084843 1020.7673496502841 945.2023975405417 944.7958178613893 835.5450284032738 832.0015887065044 827.9395014181113 827.307586958964 821.2165821763277 820.4309935769436 820.294548785899 818.5945710078213 810.2070010995708 808.5531582831444 766.5244110808981 766.5161027601171 766.5138258623662 766.5086555680871 758.5798541769387 754.6837658970485 750.5725789017914 750.4710062609795 665.954573017678 662.4210476628735 651.4655625602937 651.4179401345932 581.2581891626446 568.1052098090219 559.0537023059575 558.4930058353442 552.04376274659 550.1310960807349 539.7335729585124 530.6980332019735 499.6614835205304 494.92856083357367 435.233706072327 427.7022770745957 408.12870586233 399.8564017607123 370.0693430732656 369.8453276971715 365.0495142503048 363.63941667951735 354.64801260132117 346.60948393726653 341.989165177843 339.37336107835586 318.36371739541346 276.21924921242635 263.16105383998615 257.4095062592678 230.5394542051745 229.7783241832631 203.97168129075772 197.50423716389173 193.87937154471115 189.86642188526633 189.8158069782149 167.94413444169322 154.9235665091735 146.21953885693915; 1394.2961643571114 1393.719342476667 1393.0473530023817 1393.0323304318085 1279.1444880358706 1279.029525999178 1278.3117258870564 1277.8511493496046 1194.0294209516148 1193.55520491641 1191.803171846141 1190.142876194972 1131.3869805426043 1131.2014610712372 1065.307184157069 1065.1728501806062 1026.2656002193517 1023.6481764995549 1023.1894583037372 1020.8824631256683 945.029677885639 944.8472060076364 834.5688513399604 832.0410591694273 827.5941007424047 827.2462614157591 821.2561141287088 821.2486639204087 821.0823481158799 819.734173712501 809.9263529938959 808.6188537221137 766.5354441921298 766.5320662271353 766.529372735752 766.527196315268 757.6928179349587 754.5094493349716 750.8462144074381 750.7411664970351 665.3378262850094 662.7173237847416 651.6484222657534 651.4473245878336 580.9335911319723 565.7914495506558 559.6285365451314 557.6101494291516 553.7164417800294 551.580320250266 542.1873203593042 537.9562953749231 499.0835014858171 494.59833112880733 434.9422258377815 428.0809777403607 408.7349871641702 390.34186593933555 374.4417923110386 373.1482097680116 362.87666131667544 362.09244038798795 360.494783299182 358.00758268716345 345.3728066556723 343.90241197682917 327.22088313629024 292.87606390736664 270.97577597028067 257.46789287176034 236.09352076034293 233.97364407113355 205.7551079821526 201.29571118166086 197.03681074343967 195.1429208360364 189.3980083944257 185.31993165305994 163.70309570227732 139.8987352906945; 1393.722826160553 1393.6939431248582 1393.3363746505843 1393.2810614687987 1278.708868166372 1278.67915745777 1278.430401532881 1278.3970207009029 1192.8544668095528 1192.725495434365 1191.7874760312127 1191.7223406995438 1130.3151785668394 1130.2831382471782 1064.898005231608 1064.8890515387125 1024.5753881034814 1024.3201844633768 1022.6175950648451 1022.3779989792935 938.8342085382973 938.54766508947 831.6345837796958 831.1731216047666 828.7826041124148 828.6494902488032 822.4527809744308 821.8615706009567 821.7426971900952 820.7967718545067 805.595381443696 805.362908884127 766.5760180851346 766.5692120498613 766.5638719060429 766.5572309401017 754.4924212862007 754.3575086320516 752.375078685376 752.0047588346991 655.4231066539371 654.4166886040252 650.8460042698251 650.8009703887651 570.0353389113353 570.0098707638689 560.2661745943111 559.790097228172 553.8808024067558 552.6318574158279 547.2681863893303 546.31918731412 503.49100114273676 499.82219180705465 438.67337513395717 435.39602264929465 419.3839733284042 408.78694385310894 400.49696388034715 389.5796726114213 367.1068498276618 363.6817128017856 358.2700197126841 357.7906703939786 355.8630860915275 342.4626962886091 326.394133758693 317.69962538045297 266.13021883442957 253.45157199535447 247.71101583560358 244.7349458875783 218.23956086587486 216.58514440946942 198.10932695056687 197.27447051943255 195.89313780697773 195.84856460458346 179.2476087349453 176.75909698506598]

    is_golden = [9.666258057265139e-5 1.316794354849955e-21 0.001807884246096581 7.126406312752414e-19 0.0021662504649699746 3.363674719065765e-19 0.003835132700659214 5.970638887714765e-20 6.229527417805757e-20 0.013550066948262537 0.018327409354780038 1.604699261247204e-20 0.0013190035226186047 2.397571886580603e-20 2.476072236204317e-17 0.006677115950888814 4.0625792554449943e-20 0.015583193497272732 0.028006929966589808 7.445185185066435e-21 0.007782414774854456 3.057644832021631e-20 0.028892276060302542 2.8711191424026884e-21 1.86694013927341e-20 0.009748743725332338 1.438807943349788e-19 0.007788123587547076 0.007278285725744326 4.340218154660154e-20 4.912132825302962e-21 0.0011677394207336472 0.00019073186580998352 0.0002351390443091334 4.3253629291813217e-16 2.445602822329635e-16 0.002193318006771702 1.608230217574063e-20 0.008315770390853787 5.328418339963631e-19 0.016520647064218567 4.8690098328768624e-20 3.695523209428073e-18 0.01498917264361659 0.08363192971305818 0.0019021903483600663 4.583876063932843e-22 4.659563485507966e-22 1.2734544622768467e-21 0.01711154545199492 0.007341641472508209 4.317540813881233e-22 1.553684871008787e-21 0.151419922468914 0.0946669926335904 1.260513682534767e-20 0.21463962810706255 2.3282397935704255e-21 4.63287870467313e-18 0.07251418471117228 0.08727932967162867 4.247298373078868e-19 3.39439099744501e-21 0.23891458920773445 7.950571431303797e-21 0.40154618507105844 2.0628093343897441e-22 0.05042776642529965 0.04544662783109199 1.1094652860997299e-21 5.418482877221452e-20 0.07842778136102171 0.1923504952687675 6.785816674018066e-21 0.002594420277582628 1.8542681766252516e-16 0.03780018215099838 0.08192155891708171 5.104723435913834e-22 8.186337825260952e-22; 0.0013108253707940715 1.7232627849842074e-20 0.0018148225053177306 2.461074547417478e-17 0.0019486303659069656 4.001540934372424e-19 0.0038519214096616574 7.567594486622489e-20 7.681766901113047e-20 0.010822847808686977 0.014661304844789825 1.4480100453130606e-20 0.0035367053306356927 8.8450481713214e-20 3.1569895533314106e-17 0.007144637039314459 3.843393072073492e-20 0.009850865329995556 0.024590179018662728 6.174083534024647e-21 0.016836344005120074 3.314144796529482e-19 0.03788679901405467 5.6642582345398735e-21 4.229389627324808e-20 0.006671083204540495 3.632641717830399e-16 0.009560337172355259 0.004674005084982858 9.629247612749233e-20 2.4513010424727172e-20 0.00417701662958812 0.00011511806686506827 0.0002550033891584578 2.971394114603632e-17 4.3892691231674163e-16 0.005833032720408417 1.0110121158513564e-20 3.261003882678914e-19 0.006478977547362864 0.04602569331812337 2.5168498940921993e-19 2.5192384535935005e-19 0.017483773858048866 0.11059747979423383 0.00836623896995657 2.02514834028718e-21 6.82746449933204e-21 0.06772416969920106 1.4586092122803048e-20 0.013980810835241173 3.5911345027742344e-21 2.7414810820343003e-21 0.17639974847262238 0.04971089352763511 3.442205182676943e-21 0.16484929076688115 7.784451937675955e-22 0.38658336658941184 3.600534275694351e-19 0.22379344899163578 2.2950461910025942e-18 0.08145409434401521 4.3582157335526886e-20 9.203429304718473e-21 0.07462387237982612 1.1691308611962618e-22 0.019081019502794474 0.09544143528865189 8.934801232220134e-22 5.358789623107541e-21 0.09820474653058273 1.5870031774106964e-21 0.11893101746868029 3.911985826282614e-20 0.0010160399687993815 5.262382240798022e-22 0.10664729987188112 0.015066985995768108 3.6046010182819673e-22; 2.3412651083717832e-20 0.0001240998726697097 3.3547263850881537e-20 0.0016812884438361254 3.638770412057831e-17 0.0032559455092689713 3.253257571218432e-17 0.0031416319900203827 3.2099202133196004e-19 0.031964551255109296 0.0028594825769926164 4.120350850503572e-19 1.9921797267301347e-18 0.002555122802175514 0.005876671358878053 5.842869745793846e-15 6.716050534517139e-18 0.040866604541374855 0.00508660786937555 9.381391378748282e-19 6.105358073821092e-20 0.007079868384765627 6.530103132074549e-21 0.015807663636798537 6.294548688922584e-20 0.016031039876077208 0.002911637265694974 3.160903960094455e-18 0.013355104107631067 2.5237747974216617e-19 0.007541575080130794 2.0116829807772074e-18 7.273984507537815e-18 0.0001331845210167025 1.085354786721206e-17 0.00016426361001464134 1.8788773725133137e-18 0.003257707492421989 7.988837525227281e-19 0.01046310479712024 4.381409707000225e-19 0.032024412435506806 1.1279015786429608e-17 0.003166328487828232 0.028136393731688872 1.4285600563083653e-16 6.079339720636984e-20 0.04511604451340014 1.900035370893462e-20 0.03600766575856428 0.010924394629590871 4.871682442816673e-20 0.15343595427983436 2.0763579316208373e-21 0.029368782144637687 2.0566467750858123e-21 0.15804188264062524 5.254569293972656e-21 0.1641533347374242 6.501883368693326e-22 0.11165206946735873 1.4670994914403685e-20 4.49087627317897e-19 0.08815955165398119 0.008506692007146151 1.7338718598398136e-21 0.31758834070195907 2.2036242232522355e-21 0.019209627116006066 1.3179555547151021e-21 0.09908685214854047 3.82315761210254e-21 6.885940578414024e-20 0.14976528329476757 2.379769740365076e-19 0.021210134893023574 0.06513458885855543 3.100767273424569e-16 4.1369337732263514e-20 0.0635116799497047]

    @test isapprox(disps,disps_golden;atol = 1e-8)
    @test_broken isapprox(disps,disps_golden;atol = 1e-12)
    @test isapprox(is,is_golden;atol = 1e-12)

    # Test every component using :full. To limit size of "golden" data, restrict
    # to one arbitrary k-vector, and round to 10 digits of accuracy.
    formula = intensity_formula(swt,:full,kernel = delta_function_kernel,formfactors = [FormFactor("Fe2")])
    _, is_full = intensities_bands(swt,[ks[1]],formula)
    is_full_flattened = reinterpret(reshape, ComplexF64, is_full)[:]

    # println(round.(is_full_flattened; digits=10))
    is_full_golden = [0.0007687558, 0.0004533132 - 4.89354e-5im, 0.0004685355 + 8.58128e-5im, 0.0004533132 + 4.89354e-5im, 0.0002704208, 0.0002708195 + 8.04261e-5im, 0.0004685355 - 8.58128e-5im, 0.0002708195 - 8.04261e-5im, 0.0002951383, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0002179405, -0.0001143995 - 0.0002112938im, -0.0001260189 + 0.0001998957im, -0.0001143995 + 0.0002112938im, 0.0002648994, -0.0001276505 - 0.0002271032im, -0.0001260189 - 0.0001998957im, -0.0001276505 + 0.0002271032im, 0.0002562124, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7.50171e-5, 0.0002066251 + 0.0001586013im, 0.0002400554 - 0.0001101672im, 0.0002066251 - 0.0001586013im, 0.0009044372, 0.000428286 - 0.0008109666im, 0.0002400554 + 0.0001101672im, 0.000428286 + 0.0008109666im, 0.0009299659, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0006494893, -0.0005226637 - 0.0001595013im, -0.0005172485 + 0.0001540188im, -0.0005226637 + 0.0001595013im, 0.0004597735, 0.0003784217 - 0.0002509692im, -0.0005172485 - 0.0001540188im, 0.0003784217 + 0.0002509692im, 0.0004484567, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0003832312, -0.00115464 - 0.0001725719im, -0.0011365727 + 0.0002731129im, -0.00115464 + 0.0001725719im, 0.0035565339, 0.0033014035 - 0.0013346714im, -0.0011365727 - 0.0002731129im, 0.0033014035 + 0.0013346714im, 0.0035654413, 0.0032082429, -0.0026123812 - 4.67732e-5im, -0.0026034398 - 9.23301e-5im, -0.0026123812 + 4.67732e-5im, 0.0021278698, 0.0021212533 + 3.72261e-5im, -0.0026034398 + 9.23301e-5im, 0.0021212533 - 3.72261e-5im, 0.0021153086, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0011853379, 0.0007388392 - 0.0005298747im, 0.0007199725 + 0.0005517446im, 0.0007388392 + 0.0005298747im, 0.0006973965, 0.0002021267 + 0.0006657559im, 0.0007199725 - 0.0005517446im, 0.0002021267 - 0.0006657559im, 0.0006941333, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0005412737, 0.0004273446 - 0.0008671531im, 0.0004344266 + 0.000846893im, 0.0004273446 + 0.0008671531im, 0.0017266272, -0.0010137866 + 0.0013646137im, 0.0004344266 - 0.000846893im, -0.0010137866 - 0.0013646137im, 0.001673745, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0007626316, -0.0015089743 + 0.0006023712im, -0.0014572557 - 0.0006062548im, -0.0015089743 - 0.0006023712im, 0.0034615066, 0.0024045304 + 0.0023505867im, -0.0014572557 + 0.0006062548im, 0.0024045304 - 0.0023505867im, 0.0032665037, 0.0048422324, -0.0038499357 - 0.0006790047im, -0.00398032 + 0.0007515717im, -0.0038499357 + 0.0006790047im, 0.0031561997, 0.0030592616 - 0.001155698im, -0.00398032 - 0.0007515717im, 0.0030592616 + 0.001155698im, 0.0033884799, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0075607214, 0.0043681075 + 0.003343941im, 0.0043652524 - 0.0032061974im, 0.0043681075 - 0.003343941im, 0.0040025684, 0.0011039366 - 0.0037829937im, 0.0043652524 + 0.0032061974im, 0.0011039366 + 0.0037829937im, 0.0038799381, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0076398243, 0.005827078 - 0.0065650353im, 0.0056151625 + 0.0067277425im, 0.005827078 + 0.0065650353im, 0.0100859029, -0.0014984477 + 0.009956619im, 0.0056151625 - 0.0067277425im, -0.0014984477 - 0.009956619im, 0.0100516145, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0009364475, -0.0012468636 + 0.0001874463im, -0.0011922513 - 0.0003712282im, -0.0012468636 - 0.0001874463im, 0.0016976978, 0.0015131541 + 0.0007329338im, -0.0011922513 + 0.0003712282im, 0.0015131541 - 0.0007329338im, 0.0016650944, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0006666367, -0.0005660042 - 0.0007203763im, -0.000388849 + 0.0008373824im, -0.0005660042 + 0.0007203763im, 0.0012590106, -0.0005747362 - 0.0011311701im, -0.000388849 - 0.0008373824im, -0.0005747362 + 0.0011311701im, 0.0012786767, 0.0011315842, -0.0006103747 - 0.0007424593im, -0.0007898443 + 0.0007203504im, -0.0006103747 + 0.0007424593im, 0.0008163803, -4.65983e-5 - 0.0009067915im, -0.0007898443 - 0.0007203504im, -4.65983e-5 + 0.0009067915im, 0.0010098752, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0025929656, 0.0017444527 - 0.0007274032im, 0.0017023396 + 0.0006809728im, 0.0017444527 + 0.0007274032im, 0.0013776622, 0.0009542391 + 0.0009356901im, 0.0017023396 - 0.0006809728im, 0.0009542391 - 0.0009356901im, 0.001296463, 5.2383e-6, -3.2369e-6 + 1.35765e-5im, 1.16111e-5 - 1.14657e-5im, -3.2369e-6 - 1.35765e-5im, 3.71874e-5, -3.68914e-5 - 2.30085e-5im, 1.16111e-5 + 1.14657e-5im, -3.68914e-5 + 2.30085e-5im, 5.08334e-5, 4.1906e-6, 4.7012e-6 - 1.34246e-5im, -4.8647e-6 + 1.27456e-5im, 4.7012e-6 + 1.34246e-5im, 4.82799e-5, -4.62881e-5 - 1.2856e-6im, -4.8647e-6 - 1.27456e-5im, -4.62881e-5 + 1.2856e-6im, 4.44127e-5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0019444076, 0.0020569513 + 0.0007908438im, 0.0020525642 - 0.0007038285im, 0.0020569513 - 0.0007908438im, 0.002497667, 0.0018851017 - 0.0015794007im, 0.0020525642 + 0.0007038285im, 0.0018851017 + 0.0015794007im, 0.0024215058, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0001446787, -0.0001301653 + 0.000474686im, -0.0001939171 - 0.0004402616im, -0.0001301653 - 0.000474686im, 0.0016745368, -0.0012700192 + 0.0010323324im, -0.0001939171 + 0.0004402616im, -0.0012700192 - 0.0010323324im, 0.0015996417, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0210951081, 0.0069398789 - 0.0056674058im, 0.00661647 + 0.0056719241im, 0.0069398789 + 0.0056674058im, 0.0038056884, 0.0006528719 + 0.0036435313im, 0.00661647 - 0.0056719241im, 0.0006528719 - 0.0036435313im, 0.0036002848, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0008637214, -1.07827e-5 - 0.0015633757im, 0.0002364007 + 0.0016189523im, -1.07827e-5 + 0.0015633757im, 0.0028299169, -0.0029333297 + 0.0004076851im, 0.0002364007 - 0.0016189523im, -0.0029333297 - 0.0004076851im, 0.0030992537, 0.0130176032, 0.0113917172 + 0.0145570906im, 0.0081308929 - 0.0145927407im, 0.0113917172 - 0.0145570906im, 0.0262475437, -0.0092031548 - 0.0218625899im, 0.0081308929 + 0.0145927407im, -0.0092031548 + 0.0218625899im, 0.0214370877, 0.0157820186, 0.0058780174 + 0.0020714985im, 0.012161504 + 0.000556069im, 0.0058780174 - 0.0020714985im, 0.0024611677, 0.0046025435 - 0.001389173im, 0.012161504 - 0.000556069im, 0.0046025435 + 0.001389173im, 0.0093911556, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0020446153, -0.000750391 - 0.0021365893im, -0.0015496205 + 0.0015719762im, -0.000750391 + 0.0021365893im, 0.0025081005, -0.0010739655 - 0.0021962564im, -0.0015496205 - 0.0015719762im, -0.0010739655 + 0.0021962564im, 0.002383056, 0.0015517142, 0.001565144 + 0.0013547685im, 0.0011226199 - 0.0015728385im, 0.001565144 - 0.0013547685im, 0.0027615095, -0.0002408757 - 0.0025665866im, 0.0011226199 + 0.0015728385im, -0.0002408757 + 0.0025665866im, 0.0024064332, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0105285505, -0.005350214 - 0.015192894im, -0.0059642564 + 0.0158166274im, -0.005350214 + 0.015192894im, 0.0246424062, -0.019792876 - 0.0166439489im, -0.0059642564 - 0.0158166274im, -0.019792876 + 0.0166439489im, 0.0271393537, 0.0492395805, 0.0012278339 - 0.0197283295im, 0.0034298589 + 0.0206541542im, 0.0012278339 + 0.0197283295im, 0.0079349693, -0.0081897664 + 0.0018892374im, 0.0034298589 - 0.0206541542im, -0.0081897664 - 0.0018892374im, 0.0089025539, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0053704527, 0.0057319207 - 0.0144407639im, 0.0025184323 + 0.0160937202im, 0.0057319207 + 0.0144407639im, 0.0449479006, -0.0405869244 + 0.0239488215im, 0.0025184323 - 0.0160937202im, -0.0405869244 - 0.0239488215im, 0.049409304, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0169175977, -0.0023761922 - 0.0127538111im, 0.0021810575 + 0.0138016016im, -0.0023761922 + 0.0127538111im, 0.0099485749, -0.0107110735 - 0.0002942771im, 0.0021810575 - 0.0138016016im, -0.0107110735 + 0.0002942771im, 0.0115407177, 0.0356811717, 0.0067007251 - 0.0194676394im, 0.0047679552 + 0.0220778665im, 0.0067007251 + 0.0194676394im, 0.0118798985, -0.0111502837 + 0.0067474955im, 0.0047679552 - 0.0220778665im, -0.0111502837 - 0.0067474955im, 0.0142978933, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0314394074, -0.0139551947 - 0.0273498935im, -0.0253858817 + 0.0215175828im, -0.0139551947 + 0.0273498935im, 0.0299867018, -0.00745048 - 0.0316349225im, -0.0253858817 - 0.0215175828im, -0.00745048 + 0.0316349225im, 0.0352248801, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0062885903, -0.0174087625 - 0.0170194535im, -0.0111393622 + 0.019230695im, -0.0174087625 + 0.0170194535im, 0.0942543206, -0.0212087929 - 0.0833841024im, -0.0111393622 - 0.019230695im, -0.0212087929 + 0.0833841024im, 0.078539863, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.038339218, -0.001324652 - 0.0128574335im, 0.0048053206 - 0.0025884822im, -0.001324652 + 0.0128574335im, 0.0043576345, 0.0007020451 + 0.0017009457im, 0.0048053206 + 0.0025884822im, 0.0007020451 - 0.0017009457im, 0.0007770463, 0.0095670645, 0.0121763694 - 0.0019013794im, 0.002807541 + 0.0118428302im, 0.0121763694 + 0.0019013794im, 0.0158752161, 0.0012195949 + 0.0156308004im, 0.002807541 - 0.0118428302im, 0.0012195949 - 0.0156308004im, 0.0154838418, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0108787148, 0.0038844623 + 0.0119337651im, 0.0041637732 - 0.0140657208im, 0.0038844623 - 0.0119337651im, 0.0144781623, -0.0139430983 - 0.0095900348im, 0.0041637732 + 0.0140657208im, -0.0139430983 + 0.0095900348im, 0.0197800489, 0.0111437327, -0.0034770451 + 0.0213410983im, 0.0001965284 - 0.0178538184im, -0.0034770451 - 0.0213410983im, 0.041954732, -0.0342527448 + 0.0051943456im, 0.0001965284 + 0.0178538184im, -0.0342527448 - 0.0051943456im, 0.0286077802, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0009391652, 0.000139209 + 0.0004654881im, -0.0003537252 - 0.0001064528im, 0.000139209 - 0.0004654881im, 0.0002513491, -0.0001051937 + 0.0001595414im, -0.0003537252 + 0.0001064528im, -0.0001051937 - 0.0001595414im, 0.0001452926, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.004802795, 0.0007628761 + 0.0067693392im, 0.0016156659 - 0.0047440337im, 0.0007628761 - 0.0067693392im, 0.0096622764, -0.0064298852 - 0.0030307562im, 0.0016156659 + 0.0047440337im, -0.0064298852 + 0.0030307562im, 0.0052295033, 0.0021334305, -0.0055930593 + 0.0007131289im, -0.0063925121 - 0.0044452898im, -0.0055930593 - 0.0007131289im, 0.0149012893, 0.015272883 + 0.0137906783im, -0.0063925121 + 0.0044452898im, 0.015272883 - 0.0137906783im, 0.0284165857, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0]
    
    @test isapprox(is_full_flattened, is_full_golden; atol=1e-9)
end

@testitem "Lanczos Bounds" begin
    using LinearAlgebra, Random

    Random.seed!(100)
    A = randn(ComplexF64, 500, 500)
    A = 0.5(A' + A)
    lo, hi = Sunny.eigbounds(A, 20)
    vals = eigvals(A)

    @test (abs(lo/vals[1] - 1) < 0.025) && (abs(hi/vals[end] - 1) < 0.025)
end

@testitem "Single Ion" begin
    # Tetragonal crystal
    a = 1.0
    c = 1.5
    latvecs = lattice_vectors(a, a, c, 90, 90, 90)
    positions = [[0, 0, 0]]
    cryst = Crystal(latvecs, positions)

    # System
    J, J′, D = 1.0, 0.1, 5.0
    infos = [SpinInfo(1, S=1, g=2)]
    sys = System(cryst, (1, 1, 1), infos, :SUN; seed=0)
    set_exchange!(sys, J,  Bond(1, 1, [1, 0, 0]))
    set_exchange!(sys, J′, Bond(1, 1, [0, 0, 1]))
    S = spin_operators(sys, 1)
    set_onsite_coupling!(sys, D * S[3]^2, 1)

    # Reshape to sheared supercell and minimize energy
    A = [1 1 1; -1 1 0; 0 0 1]
    sys = reshape_supercell(sys, A)
    randomize_spins!(sys)
    @test minimize_energy!(sys) > 0

    k = rand(Float64, 3)
    swt = SpinWaveTheory(sys)
    ωk_num = dispersion(swt, [k])[1, :]

    function single_ion_analytical_disp(k)
        γkxy = cos(2π*k[1]) + cos(2π*k[2])
        γkz  = cos(2π*k[3])
        x = 1/2 - D/(8*(2*J+J′))
        Ak₊ = -8 * (x-1) * x * (2*J+J′) - (x-1) * D + 2 * (2*x-1) * (J *γkxy + J′*γkz)
        Bk₊ = -2 * (J * γkxy + J′ * γkz)
        Ak₋ = -16 * (x-1) * x * (2*J+J′) - (2*x-1) * D - 2 * (1-2*x)^2*(J*γkxy + J′*γkz)
        Bk₋ = 2 * (1-2*x)^2 * (J*γkxy + J′*γkz)
        ωk₊ = √(Ak₊^2-Bk₊^2)
        ωk₋ = √(Ak₋^2-Bk₋^2)
        return ωk₊, ωk₋
    end
    ωk1, ωk2 = single_ion_analytical_disp(k)
    ωk3, ωk4 = single_ion_analytical_disp(k + [0.5, 0.5, 0.5])
    ωk_ref = sort([ωk1, ωk2, ωk3, ωk4]; rev=true)

    @test ωk_num ≈ ωk_ref
end

@testitem "Intensities" begin
    using LinearAlgebra

    # Crystal
    a = 8.289
    latvecs = lattice_vectors(a, a, a, 90, 90, 90)
    types = ["MzR1"]
    positions = [[0, 0, 0]]
    fcc = Crystal(latvecs, positions, 225; types)

    S = 5/2
    J = 22.06 * meV_per_K
    K = 0.15  * meV_per_K
    C = J + K
    J₁ = diagm([J, J, C])
    D = 25/24

    dims = (1, 1, 1)
    infos = [SpinInfo(1; S, g=2)]

    function compute(mode)
        sys = System(fcc, dims, infos, mode)
        set_exchange!(sys, J₁, Bond(1, 2, [0, 0, 0]))
        S = spin_operators(sys, 1)
        Λ = D * (S[1]^4 + S[2]^4 + S[3]^4)
        set_onsite_coupling!(sys, Λ, 1)
        set_dipole!(sys, (1, 1, 1), position_to_site(sys, (0, 0, 0)))
        set_dipole!(sys, (1, -1, -1), position_to_site(sys, (1/2, 1/2, 0)))
        set_dipole!(sys, (-1, -1, 1), position_to_site(sys, (1/2, 0, 1/2)))
        set_dipole!(sys, (-1, 1, -1), position_to_site(sys, (0, 1/2, 1/2)))
        swt = SpinWaveTheory(sys)
        k = [0.8, 0.6, 0.1]
        _, Sαβs =  Sunny.dssf(swt, [k])

        sunny_trace = [real(tr(Sαβs[1,a])) for a in axes(Sαβs)[2]]
        sunny_trace = filter(x -> abs(x) > 1e-12, sunny_trace)

        return sunny_trace
    end

    reference = [1.1743243223274487, 1.229979802236658, 1.048056653379038]
    @test compute(:SUN) ≈ compute(:dipole) ≈ reference
end

@testitem "Biquadratic interactions" begin
    # Cubic crystal
    a = 2.0
    latvecs = lattice_vectors(a, a, a, 90, 90, 90)
    positions = [[0, 0, 0]]
    cryst = Crystal(latvecs, positions)
    
    function test_biquad(mode, k, S)
        # System
        dims = (2, 2, 2)
        infos = [SpinInfo(1; S, g=2)]
        sys = System(cryst, dims, infos, mode)        
        α = -0.4π
        J = 1.0
        JL, JQ = J * cos(α), J * sin(α) / S^2
        set_exchange!(sys, JL, Bond(1, 1, [1, 0, 0]); biquad=JQ)

        # Initialize Néel order
        sys = reshape_supercell(sys, [1 1 1; -1 1 0; 0 0 1])
        set_dipole!(sys, ( 1, 0, 0), position_to_site(sys, (0, 0, 0)))
        set_dipole!(sys, (-1, 0, 0), position_to_site(sys, (0, 1, 0)))

        # Numerical result
        swt = SpinWaveTheory(sys)
        disp = dispersion(swt, [k])

        # Analytical result
        γk = 2 * (cos(2π*k[1]) + cos(2π*k[2]) + cos(2π*k[3]))
        disp_ref = J * (S*cos(α) - (2*S-2+1/S) * sin(α)) * √(36 - γk^2)
        
        @test disp[end-1] ≈ disp[end] ≈ disp_ref
    end

    k = [0.12, 0.23, 0.34]
    for mode in (:SUN, :dipole), S in (1, 3/2)
        test_biquad(mode, k, S)
    end
end

@testitem "Canted AFM" begin

    function test_canted_afm(S)
        J, D, h = 1.0, 0.54, 0.76
        a = 1
        latvecs = lattice_vectors(a, a, 10a, 90, 90, 90)
        positions = [[0, 0, 0]]
        cryst = Crystal(latvecs, positions)
        q = [0.12, 0.23, 0.34]
        
        dims = (2, 2, 1)
        sys = System(cryst, dims, [SpinInfo(1; S, g=1)], :dipole; units=Units.theory)
        set_exchange!(sys, J, Bond(1, 1, [1, 0, 0]))
        Sz = spin_operators(sys,1)[3]
        set_onsite_coupling!(sys, D*Sz^2, 1)
        set_external_field!(sys, [0, 0, h])

        # Numerical
        sys_swt_dip = reshape_supercell(sys, [1 -1 0; 1 1 0; 0 0 1])
        c₂ = 1 - 1/(2S)
        θ = acos(h / (2S*(4J+D*c₂)))
        set_dipole!(sys_swt_dip, ( sin(θ), 0, cos(θ)), position_to_site(sys_swt_dip, (0,0,0)))
        set_dipole!(sys_swt_dip, (-sin(θ), 0, cos(θ)), position_to_site(sys_swt_dip, (1,0,0)))
        swt_dip = SpinWaveTheory(sys_swt_dip)
        ϵq_num = dispersion(swt_dip, [q])[1,:]

        # Analytical
        c₂ = 1 - 1/(2S)
        θ = acos(h / (2S*(4J+c₂*D)))
        Jq = 2J*(cos(2π*q[1])+cos(2π*q[2]))
        ωq₊ = real(√Complex(4J*S*(4J*S+2D*S*c₂*sin(θ)^2) + cos(2θ)*(Jq*S)^2 + 2S*Jq*(4J*S*cos(θ)^2 + c₂*D*S*sin(θ)^2)))
        ωq₋ = real(√Complex(4J*S*(4J*S+2D*S*c₂*sin(θ)^2) + cos(2θ)*(Jq*S)^2 - 2S*Jq*(4J*S*cos(θ)^2 + c₂*D*S*sin(θ)^2)))
        ϵq_ana = [ωq₊, ωq₋]

        ϵq_num ≈ ϵq_ana
    end

    @test test_canted_afm(1)
    @test test_canted_afm(2)
end

@testitem "Local stevens expansion" begin
    using LinearAlgebra
    a = 1
    latvecs = lattice_vectors(a, a, 10a, 90, 90, 90)
    positions = [[0, 0, 0]]
    # P1 point group for most general single-ion anisotropy
    cryst = Crystal(latvecs, positions, 1)

    dims = (1, 1, 1)
    S = 3
    sys_dip = System(cryst, dims, [SpinInfo(1; S, g=1)], :dipole)
    sys_SUN = System(cryst, dims, [SpinInfo(1; S, g=1)], :SUN)

    # The strengths of single-ion anisotropy (must be negative to favor the dipolar ordering under consideration)
    Ds = -rand(3)
    h  = rand()
    # Random magnetic moment
    M = normalize(rand(3))
    θ, ϕ = Sunny.dipole_to_angles(M)

    s_mat = Sunny.spin_matrices(N=2S+1)
    
    s̃ᶻ = M' * spin_operators(sys_dip,1)
    
    U_mat = exp(-1im * ϕ * s_mat[3]) * exp(-1im * θ * s_mat[2])
    hws = zeros(2S+1)
    hws[1] = 1.0
    Z = U_mat * hws

    aniso = Ds[1]*s̃ᶻ^2 + Ds[2]*s̃ᶻ^4 + Ds[3]*s̃ᶻ^6

    set_onsite_coupling!(sys_dip, aniso, 1)
    
    s̃ᶻ = M' * spin_operators(sys_SUN,1)
    aniso = Ds[1]*s̃ᶻ^2 + Ds[2]*s̃ᶻ^4 + Ds[3]*s̃ᶻ^6
    set_onsite_coupling!(sys_SUN, aniso, 1)

    set_external_field!(sys_dip, h*M)
    set_external_field!(sys_SUN, h*M)

    set_dipole!(sys_dip, M, position_to_site(sys_dip, (0, 0, 0)))
    set_coherent!(sys_SUN, Z, position_to_site(sys_SUN, (0, 0, 0)))

    energy(sys_dip)
    energy(sys_SUN)

    q = rand(3)

    swt_dip = SpinWaveTheory(sys_dip)
    swt_SUN = SpinWaveTheory(sys_SUN)

    disp_dip = dispersion(swt_dip, [q])
    disp_SUN = dispersion(swt_SUN, [q])

    @test disp_dip[1] ≈ disp_SUN[end-1]
end

@testitem "Intensities interface" begin
    sys = System(Sunny.diamond_crystal(),(1,1,1),[SpinInfo(1,S=1/2,g=2)],:SUN;seed = 0)
    randomize_spins!(sys)

    swt = SpinWaveTheory(sys)
    
    # Just testing that nothing throws errors
    # TODO: accuracy check
    path, _ = reciprocal_space_path(Sunny.diamond_crystal(),[[0.,0.,0.],[0.5,0.5,0.]],50)
    energies = collect(0:0.1:5)

    # Bands
    formula = intensity_formula(swt,:perp,kernel = delta_function_kernel)
    intensities_bands(swt,path,formula)
    @test_throws "without a finite-width kernel" intensities_broadened(swt,path,energies,formula)

    # Broadened
    formula = intensity_formula(swt,:perp,kernel = lorentzian(0.05))
    intensities_broadened(swt,path,energies,formula)
    @test_throws "broadening kernel" intensities_bands(swt,path,formula)

    formula = intensity_formula(swt,:perp,kernel = (w,dw) -> lorentzian(dw,w.^2))
    intensities_broadened(swt,path,energies,formula)
    @test_throws "broadening kernel" intensities_bands(swt,path,formula)

    # Full
    formula = intensity_formula(swt,:full,kernel = lorentzian(0.05))
    intensities_broadened(swt,path,energies,formula)
end

@testitem "Dipole-dipole unimplemented" begin
    sys = System(Sunny.diamond_crystal(),(1,1,1),[SpinInfo(1,S=1/2,g=2)],:SUN;seed = 0)
    enable_dipole_dipole!(sys)
    @test_throws "SpinWaveTheory does not yet support long-range dipole-dipole interactions." SpinWaveTheory(sys)
end

@testitem "Langasite" begin
    a = b = 8.539
    c = 5.2414
    latvecs = lattice_vectors(a, b, c, 90, 90, 120)
    crystal = Crystal(latvecs, [[0.24964,0,0.5]], 150)
    latsize = (1,1,7)
    sys = System(crystal, latsize, [SpinInfo(1; S=5/2, g=2)], :dipole; seed=5)
    set_exchange!(sys, 0.85,  Bond(3, 2, [1,1,0]))   # J1
    set_exchange!(sys, 0.24,  Bond(1, 3, [0,0,0]))   # J2
    set_exchange!(sys, 0.053, Bond(2, 3, [-1,-1,1])) # J3
    set_exchange!(sys, 0.017, Bond(1, 1, [0,0,1]))   # J4
    set_exchange!(sys, 0.24,  Bond(3, 2, [1,1,1]))   # J5
    
    # TODO: Use helper function to initialize single-Q state
    function R(site)
        R1=[0.5 0.5im 0; -0.5im 0.5 0; 0 0 0]
        R2=[0 0 0; 0 0 0; 0 0 1]
        return exp((site-1)*2π*im/7)*R1 + exp(-(site-1)*2π*im/7)*conj(R1) + R2
    end
    S1=[1.0, 0, 0]*(5/2)
    S2=[-0.5, -sqrt(3)/2, 0]*(5/2)
    S3=[-0.5, sqrt(3)/2, 0]*(5/2)
    for site in 1:7
        set_dipole!(sys, R(site)*S1, (1,1,site,1))
        set_dipole!(sys, R(site)*S2, (1,1,site,2))
        set_dipole!(sys, R(site)*S3, (1,1,site,3))
    end
    
    swt = SpinWaveTheory(sys)
    formula = intensity_formula(swt, :full; kernel=delta_function_kernel)
    q = [0.41568,0.56382,0.76414]
    disp, intensities = intensities_bands(swt, [q], formula)
    SpinW_energies=[2.6267,2.6541,2.8177,2.8767,3.2458,3.3172,3.4727,3.7767,3.8202,3.8284,3.8749,3.9095,3.9422,3.9730,4.0113,4.0794,4.2785,4.4605,4.6736,4.7564,4.7865]
    SpinW_intensities = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0.2999830079, -0.2999830079im, 0,0.2999830079im, 0.2999830079, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.3591387785, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.5954018134, -0.5954018134im, 0,0.5954018134im, 0.5954018134, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1.3708506016,1.3708506016im, 0, -1.3708506016im, 1.3708506016, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0511743697, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0734875342, 0.0 + 0.0734875342im, 0, 0.0 - 0.0734875342im, 0.0734875342, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0577275935, -0.0577275935im, 0,0.0577275935im, 0.0577275935, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6.1733740706, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0338873034,0.0338873034im, 0, -0.0338873034im, 0.0338873034, 0, 0, 0, 0]
    
    @test isapprox(disp[:], reverse(SpinW_energies); atol=1e-3)
    
    intensities_reshaped = reinterpret(reshape, ComplexF64, intensities)[:]
    @test isapprox(SpinW_intensities/Sunny.natoms(crystal), intensities_reshaped; atol=1e-7)    
end
