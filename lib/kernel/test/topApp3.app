    {application, topApp3,
     [{description, "Test of start phase"},
      {id, "CXC 138 38"},
      {vsn, "2.0"},
      {applications, [kernel]},
      {modules, []},
      {registered, []},
      {env, [{own_env1, value1}, {own2, val2}]},
      {included_applications, [appinc1x, appinc2top]},
      {start_phases, [{top, [topArgs]}, {init, [initArgs]}, {some, [someArgs]}, 
		      {spec, [specArgs]}, {go, [goArgs]}]},
      {mod, {application_starter, [topApp3, {topApp3, 4, 6}]} }]}. 