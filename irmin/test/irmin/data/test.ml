let () =
  Random.self_init ();
  Alcotest.run ~__FILE__ "Data"
    [ ("Fixed_size_string_set", Test_fixed_size_string_set.tests) ]
