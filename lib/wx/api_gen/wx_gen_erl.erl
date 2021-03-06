%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 2008-2009. All Rights Reserved.
%% 
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%% 
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%% 
%% %CopyrightEnd%
%%
%%%-------------------------------------------------------------------
%%% File    : wx_gen_erl.erl
%%% Author  : Dan Gudmundsson <dgud@erix.ericsson.se>
%%% Description : 
%%%
%%% Created : 25 Jan 2007 by Dan Gudmundsson <dgud@erix.ericsson.se>
%%%-------------------------------------------------------------------

-module(wx_gen_erl).

-include("wx_gen.hrl").

-compile(export_all).

-import(lists, [foldl/3,foldr/3,reverse/1, keysearch/3, map/2, filter/2]).
-import(gen_util, [lowercase/1, lowercase_all/1, uppercase/1, uppercase_all/1,
		   open_write/1, close/0, erl_copyright/0, w/2, 
		   args/3, args/4, strip_name/2]).

gen(Defs) ->
    [put({class,N},C) || C=#class{name=N} <- Defs],
    gen_unique_names(Defs),
    gen_event_recs(),
    gen_enums_ints(),
    [gen_class(Class) || Class <- Defs],
    gen_funcnames().
        
gen_class(Class) ->
    try 
	gen_class1(Class)
    catch throw:skipped ->
	    Class
    end.

gen_class1(C=#class{name=Name,parent="static",methods=Ms,options=_Opts}) ->
    open_write("../src/gen/wx_misc.erl"),
    put(current_class, Name), 
    erl_copyright(),
    w("", []),
    w("%% This file is generated DO NOT EDIT~n~n", []),    
    w("%% @doc See external documentation: "
      "<a href=\"http://www.wxwidgets.org/manuals/stable/wx_miscellany.html\">Misc</a>.\n\n",[]),

    w("%% This module contains wxWidgets utility functions.~n~n", []),
    w("-module(wx_misc).~n", []),
    w("-include(\"wxe.hrl\").~n",[]),
    %% w("-compile(export_all).~n~n", []),            %% XXXX remove ???

    Exp = fun(M) -> gen_export(C,M) end,
    ExportList = lists:usort(lists:append(lists:map(Exp,reverse(Ms)))),
    w("-export([~s]).~n~n", [args(fun(EF) -> EF end, ",", ExportList, 60)]),
    
    
    Gen = fun(M) -> gen_method(Name,M) end,
    NewMs = lists:map(Gen,reverse(Ms)),
    close(),
    erase(current_class),
    C#class{methods=NewMs};

gen_class1(C=#class{name=Name,parent=Parent,methods=Ms,options=Opts}) ->
    case Opts of
	["ignore"] -> throw(skipped);
	_ -> ok
    end,    
    open_write("../src/gen/"++Name++".erl"),
    put(current_class, Name), 
    erl_copyright(),
    w("", []),
    w("%% This file is generated DO NOT EDIT~n~n", []),    
    
    case lists:member(taylormade, Opts) of
	true ->
	    {ok, Bin} = file:read_file(filename:join([wx_extra, Name++".erl"])),
	    w("~s~n", [binary_to_list(Bin)]),
	    NewMs = Ms;
	false ->
	    w("%% @doc See external documentation: "
	      "<a href=\"http://www.wxwidgets.org/manuals/stable/wx_~s.html\">~s</a>.\n",
	      [lowercase_all(Name), Name]),
	    
	    case C#class.doc of
		undefined -> ignore;
		Str -> w("%%~n%% ~s~n~n%%~n", [Str])
	    end,
	    
	    case C#class.event of
		false -> ignore;
		Evs ->
		    EvTypes = [event_type_name(Ev) || Ev <- Evs],
		    EvStr = args(fun(Ev) -> "<em>"++Ev++"</em>" end, ", ", EvTypes),
		    
		    w("%% <dl><dt>Use {@link wxEvtHandler:connect/3.} with EventType:</dt>~n",[]),
		    w("%% <dd>~s</dd></dl>~n", [EvStr]),
		    w("%% See also the message variant {@link wxEvtHandler:~s(). #~s{}} event record type.~n", 
		      [event_rec_name(Name),event_rec_name(Name)]),
		    w("%%~n",[]),
		    ok
	    end,
	    
	    Parents = parents(Parent),
	    case [P || P <- Parents, P =/= root, P =/= object] of
		[] -> ignore;
		Ps -> 
		    w("%% <p>This class is derived (and can use functions) from: ~n", []),
		    [w("%% <br />{@link ~s}~n", [P]) || P <- Ps],
		    w("%% </p>~n",[])		    
	    end,
	    w("%% @type ~s().  An object reference, The representation is internal~n",[Name]),
	    w("%% and can be changed without notice. It can't be used for comparsion~n", []),
	    w("%% stored on disc or distributed for use on other nodes.~n~n", []),
	    w("-module(~s).~n", [Name]),
	    w("-include(\"wxe.hrl\").~n",[]),
	    %% w("-compile(export_all).~n~n", []),            %% XXXX remove ???
	    %%    w("-compile(nowarn_unused_vars).~n~n", []),  %% XXXX remove ???
	    Exp = fun(M) -> gen_export(C,M) end,
	    ExportList = lists:usort(lists:append(lists:map(Exp,reverse(Ms)))),
	    w("-export([~s]).~n~n", [args(fun(EF) -> EF end, ",", ExportList, 60)]),
	    w("%% inherited exports~n",[]),
	    Done0 = ["Destroy", "New", "Create", "destroy", "new", "create"],
	    Done  = gb_sets:from_list(Done0 ++ [M|| #method{name=M} <- lists:append(Ms)]),
	    {_, InExported} = gen_inherited(Parents, Done, []),
	    w("-export([~s]).~n~n", [args(fun(EF) -> EF end, ",", 
					  lists:usort(["parent_class/1"|InExported]), 
					  60)]),
    
	    w("%% @hidden~n", []),
	    parents_check(Parents),
	    
	    Gen = fun(M) -> gen_method(Name,M) end,
	    NewMs = lists:map(Gen,reverse(Ms)),
	    gen_dest(C, Ms),	    
	    
	    gen_inherited(Parents, Done, true)
    end,

    close(),
    erase(current_class),
    C#class{methods=NewMs}.


parents("root") -> [root];
parents("object") -> [object];
parents(Parent) ->
    case get({class,Parent}) of
	#class{parent=GrandParent} ->
	    [Parent|parents(GrandParent)];
	undefined ->
	    ?warning("unknown parent of ~p~n",[Parent]),
	    [Parent]
    end.

parents_check([object]) ->
    w("parent_class(_Class) -> erlang:error({badtype, ?MODULE}).~n~n",[]);
parents_check([root]) ->
    w("parent_class(_Class) -> erlang:error({badtype, ?MODULE}).~n~n",[]);
parents_check([Parent|Ps]) ->
    w("parent_class(~s) -> true;~n",[Parent]),
    parents_check(Ps).

check_class(#type{base={class,"wx"}}) -> ok;
check_class(#type{base={class,Name},xml=Xml}) ->
    case get({class,Name}) of
	undefined ->
	    case get({enum, Name}) of
		undefined ->
		    case Xml of
			"class" ++ _ ->
			    ?warning("~s:~s: Class ~p used but not defined~n",
				     [get(current_class),get(current_func),Name]);
			_ ->
			    ?warning("~s:~s: Class ~p used but not defined~n   (see ~p)~n",
				     [get(current_class),get(current_func),Name, Xml])
		    end;
		_ ->
		    ?warning("~s:~s: Class ~p used is enum~n",
			     [get(current_class),get(current_func),Name])
	    end;
	_ -> ok
    end.

gen_export(#class{name=Class,abstract=Abs},Ms0) ->
    RemoveC = fun(#method{where=merged_c}) -> false;(_Other) -> true end,
    Res = filter(RemoveC, Ms0),
    case Res of
	[] -> [];
	[M=#method{where=taylormade}|_] ->
	    [taylormade_export(Class, M)];
	Ms -> 
	    GetF = fun(#method{method_type=constructor,where=W,params=Ps}) ->
			   {Args,Opts} = split_optional(Ps),
			   OptLen = case Opts of 
					[] -> 0; 
					_ when W =:= erl_no_opt -> 0;
					_ -> 1 
				    end,
			   "new/" ++ integer_to_list(length(Args)+OptLen);
		      (#method{method_type=destructor}) ->
			   case Abs of 
			       true -> []; 
			       _ -> "destroy/1"
			   end;
		      (#method{name=N,alias=A,where=W, params=Ps}) ->
			   {Args,Opts} = split_optional(Ps),
			   OptLen = case Opts of 
					[] -> 0; 
					_ when W =:= erl_no_opt -> 0;
					_ -> 1 
				    end,
			   erl_func_name(N,A) ++ "/" ++ integer_to_list(length(Args) + OptLen)
		   end,
	    lists:map(GetF, Ms)
    end.


gen_method(Class,Ms0) ->
    RemoveC = fun(#method{where=merged_c}) -> false;(_Other) -> true end,
    Res = filter(RemoveC, Ms0),
    case Res of
	[] -> Ms0;
	[M=#method{where=taylormade}|_] ->
	    taylormade_func(Class, M),
	    Ms0;
	Ms -> 
 	    gen_doc(Class,Ms),
	    gen_method1(Ms),
	    Ms0
    end.

gen_method1([M=#method{method_type=destructor}]) ->
    %% Skip now do destructors later
    M;
gen_method1([M0]) ->
    gen_method2(M0),
    w(".~n~n",[]);
gen_method1([M0|Ms]) ->
    gen_method2(M0),
    w(";~n",[]),
    gen_method1(Ms).

gen_method2(M=#method{name=N,alias=A,params=Ps0,where=erl_no_opt,method_type=MT}) ->
    put(current_func, N),
    Ps = [patch_param(P,classes) || P <- Ps0],
    w("~n", []),
    gen_function_clause(erl_func_name(N,A),MT,Ps,[],[name_type]),
    w("  ", []),
    gen_function_clause(erl_func_name(N,A),MT,Ps,empty_list,[no_guards,name_only]),
    M;
gen_method2(M=#method{name=N,alias=A,params=Ps,type=T,method_type=MT,id=MethodId}) ->
    put(current_func, N),
    {Args, Optional} = split_optional(Ps),
    gen_function_clause(erl_func_name(N,A),MT, Args, Optional, []),
    MId = arg_type_tests(Args, "?" ++ get_unique_name(MethodId)),
    {MArgs,Align} = marshal_args(Args),
    MOpts = marshal_opts(Optional, Align, Args),
    case have_return_vals(T, Ps) of
	_ when MT =:= constructor ->
	    w("  wxe_util:construct(~s,~n  <<~s~s>>)", [MId, MArgs,MOpts]);
	true ->
	    w("  wxe_util:call(~s,~n  <<~s~s>>)", [MId, MArgs,MOpts]);
	false -> 
	    w("  wxe_util:cast(~s,~n  <<~s~s>>)", [MId, MArgs,MOpts])
    end,
    erase(current_func),
    M.

gen_dest(#class{name=CName,abstract=Abs}, Ms) ->
    case Abs of
	true ->
	    ignore;
	false ->
	    case lists:keysearch(destructor,#method.method_type, lists:append(Ms)) of
		{value, #method{method_type=destructor, id=Id}} ->
		    case hd(reverse(parents(CName))) of
			object -> 
			    gen_dest2(CName, object);
			root -> 
			    gen_dest2(CName, Id)
		    end;
		false ->
		    erlang:error({no_destructor_found, CName})
	    end
    end.

gen_dest2(Class, Id) ->
    w("%% @spec (This::~s()) -> ok~n", [Class]),
    w("%% @doc Destroys this object, do not use object again~n", []),
    w("destroy(Obj=#wx_ref{type=Type}) -> ~n", []),
    w("  ?CLASS(Type,~s),~n",[Class]), 
    case Id of
	object ->
	    w("  wxe_util:destroy(?DESTROY_OBJECT,Obj),~n  ok.~n", []);
	_ ->
	    w("  wxe_util:destroy(?~s,Obj),~n  ok.~n", [get_unique_name(Id)])
    end,
    ok.

gen_inherited([root], Done, Exported) -> {Done, Exported};
gen_inherited([object], Done, Exported) -> {Done, Exported};
gen_inherited([Parent|Ps], Done0, Exported0) ->
    #class{name=Class, methods=Ms} = get({class,Parent}),
    case is_list(Exported0) of
	false -> w(" %% From ~s ~n", [Class]);
	true  -> ignore
    end,
    {Done,Exported} = gen_inherited_ms(Ms, Class, Done0, gb_sets:empty(), Exported0),
    gen_inherited(Ps, gb_sets:union(Done,Done0), Exported).

gen_inherited_ms([[#method{name=Name,alias=A,params=Ps0,where=W,method_type=MT}|_]|R],
		 Class,Skip,Done, Exported) 
  when W =/= merged_c ->    
    case gb_sets:is_member(Name,Skip) of
	false when MT =:= member, Exported =:= true ->
	    Ps = [patch_param(P,all) || P <- Ps0],
	    Opts = if W =:= erl_no_opt -> [];
		      true -> 
			   [Opt || Opt = #param{def=Def,in=In, where=Where} <- Ps, 
				   Def =/= none, In =/= false, Where =/= c]
		   end,
	    w("%% @hidden~n", []),
	    gen_function_clause(erl_func_name(Name,A),MT,Ps,Opts,[no_guards,name_only]),
	    w(" -> ~s:", [Class]),
	    gen_function_clause(erl_func_name(Name,A),MT,Ps,Opts,[no_guards,name_only]),
	    w(".~n", []),
	    gen_inherited_ms(R,Class, Skip, gb_sets:add(Name,Done), Exported);
	false when MT =:= member, is_list(Exported) ->
	    {Args,Opts} = split_optional(Ps0),
	    OptLen = case Opts of 
			 [] -> 0; 
			 _ when W =:= erl_no_opt -> 0;
			 _ -> 1 
		     end,
	    Export = erl_func_name(Name,A) ++ "/" ++ integer_to_list(length(Args) + OptLen),
	    gen_inherited_ms(R,Class,Skip, gb_sets:add(Name,Done), [Export|Exported]);
	_ ->
	    gen_inherited_ms(R,Class, Skip, Done, Exported)
    end;
gen_inherited_ms([[_|Check]|R],Class,Skip, Done0,Exp) ->
    gen_inherited_ms([Check|R],Class,Skip, Done0,Exp);
gen_inherited_ms([[]|R],Class,Skip,Done0,Exp) ->
    gen_inherited_ms(R,Class,Skip,Done0,Exp);
gen_inherited_ms([], _, _Skip, Done,Exp) -> {Done,Exp}.
    

%%%%%%%%%%%%%%%

taylormade_func(Class, #method{name=Name, id=Id}) ->
    {ok, Bin} = file:read_file(filename:join([wx_extra, Class ++".erl"])),
    Str0 = binary_to_list(Bin),
    {match, [Str1]} = re:run(Str0, "<<"++Name++"(.*)"++Name++">>",
			     [dotall, {capture, all_but_first, list}]),
    
    w(Str1, ["?" ++ get_unique_name(Id)]),
    ok.

taylormade_export(Class, #method{name=Name}) ->
    {ok, Bin} = file:read_file(filename:join([wx_extra, Class ++".erl"])),
    Str0 = binary_to_list(Bin),
    {match, [Str1]} = re:run(Str0, "<<EXPORT:"++Name++"(.*)"++Name++":EXPORT>>",
			     [dotall, {capture, all_but_first, list}]),
    Str1.

%%%%%%%%%%%%%%%

arg_type_tests([P|Ps], Mid0) ->
    case arg_type_test(P,"\n",Mid0) of
	Mid0 -> 
	    arg_type_tests(Ps, Mid0);
	Mid ->  %% Already checked the other args
	    Mid
    end;
arg_type_tests([],Mid) -> Mid.        

arg_type_test(#param{where=c}, _, Acc) ->
    Acc;
arg_type_test(#param{name=Name0,in=In,type=#type{base={class,T},single=true},def=none},
	      EOS,Acc) when In =/= false ->
    Name = erl_arg_name(Name0),
    w("  ?CLASS(~sT,~s),~s", [Name,T,EOS]),
    Acc;
arg_type_test(#param{name=Name0,in=In,type=#type{base={class,T}}, def=none},EOS,Acc) 
  when In =/= false ->
    Name = erl_arg_name(Name0),
    w("  [?CLASS(~sT,~s) || #wx_ref{type=~sT} <- ~s],~s", [Name,T,Name,Name,EOS]),
    Acc;
arg_type_test(#param{name=Name0,def=none,in=In,
		     type={merged,
			   M1, #type{base={class,T1},single=true},Ps1,
			   M2, #type{base={class,T2},single=true},Ps2}}, EOS, _Acc) 
  when In =/= false ->
    Name = erl_arg_name(Name0),
    Opname = Name++"OP",
    w("  ~s = case ?CLASS_T(~sT,~s) of~n     true ->\n       ", [Opname,Name,T1]),
    lists:foreach(fun(Param) -> arg_type_test(Param,"\n       ", ignore) end, 
		  element(1,split_optional(Ps1))),
    w("?~s;~n",[get_unique_name(M1)]),
    w("     _ -> ?CLASS(~sT,~s),\n       ",[Name,T2]),
    {Ps21,_} = split_optional(patchArgName(Ps2,Ps1)),
    lists:foreach(fun(Param) -> arg_type_test(Param,"\n       ", ignore) end, 
		  Ps21),
    w("?~s\n     end,~s",[get_unique_name(M2),EOS]),
    Opname;
arg_type_test(#param{name=Name0, type=#type{base=eventType}}, EOS, Acc) -> 
    Name = erl_arg_name(Name0),
    w("  ~sBin = list_to_binary([atom_to_list(~s)|[0]]),~s", [Name,Name,EOS]),
    w("  ThisTypeBin = list_to_binary([atom_to_list(ThisT)|[0]]),~s", [EOS]),
    Acc;
arg_type_test(#param{name=Name0,def=none,type=#type{base={term,_}}}, EOS, Acc) -> 
    Name = erl_arg_name(Name0),
    w("  wxe_util:send_bin(term_to_binary(~s)),~s", [Name,EOS]),
    Acc;
arg_type_test(#param{name=Name0,type=#type{base=binary}},EOS,Acc) -> 
    Name = erl_arg_name(Name0),
    w("  wxe_util:send_bin(~s),~s", [Name,EOS]),
    Acc;
arg_type_test(#param{name=Name0,type=#type{name=Type,base=Base,single=Single}},EOS,Acc) -> 
    if 
	Type =:= "wxArtClient", Single =:= true ->
	    Name = erl_arg_name(Name0),
	    w("  ~s_UC = unicode:characters_to_binary([~s, $_, $C,0]),~s",
	      [Name,Name, EOS]);
	Base =:= string orelse (Type =:= "wxChar" andalso Single =/= true) ->
	    Name = erl_arg_name(Name0),
	    w("  ~s_UC = unicode:characters_to_binary([~s,0]),~s", [Name,Name,EOS]);
	Type =:= "wxArrayString" ->
	    Name = erl_arg_name(Name0),
	    w("  ~s_UCA = [unicode:characters_to_binary([~sTemp,0]) || ~s", 
	      [Name,Name, EOS]),
	    w("              ~sTemp <- ~s],~s", [Name,Name,EOS]);
	true -> %% Not a string
	    ignore 
    end,
    Acc;
arg_type_test(_,_,Acc) -> Acc.

patchArgName([Param|R1], [#param{name=Name}|R2]) ->
    [Param#param{name=Name}|patchArgName(R1,R2)];
patchArgName([],[]) -> [].

have_return_vals(void, Ps) ->
    lists:any(fun(#param{in=In}) -> In =/= true end, Ps);
have_return_vals(#type{}, _) -> true.

gen_function_clause(Name0,MT,Ps,Optional,Variant) ->
    PArg = fun(Arg) -> 
		   case lists:member(name_only, Variant) of
		       true -> func_arg_name(Arg);
		       false -> 
			   case lists:member(name_type, Variant) of
			       true ->
				   Name = func_arg_name(Arg),
				   case func_arg(Arg) of
				       Name -> Name;
				       Typed -> Name ++ "=" ++ Typed
				   end;
			       false ->
				   func_arg(Arg)
			   end
		   end
	   end,
    Args = args(PArg, ",", Ps),
    Name = case MT of constructor -> "new"; _ -> Name0 end,
    w("~s(~s",[Name,Args]),
    Opts = case Optional of 
	       [] -> "";
	       empty_list when Args =:= [] -> "[]";
	       empty_list -> ", []";
	       _ when Args =:= [] -> "Options";
	       _ -> ", Options" 
	   end,
    w("~s)", [Opts]),
    case lists:member(no_guards, Variant) of
	true ->  ok;
	false -> 
	    Guards = args(fun guard_test/1, ",", Ps),
	    if
		Guards =:= [], Opts =:= "" -> w(" ->~n", []);
		Guards =:= [] -> w("~n when is_list(Options) ->~n", []);
		Opts =:= "" -> w("~n when ~s ->~n", [Guards]);
		true -> w("~n when ~s,is_list(Options) ->~n", [Guards])
	    end
    end.

split_optional(Ps) ->
    split_optional(Ps, [], []).
split_optional([P=#param{def=Def,in=In, where=Where}|Ps], Standard, Opts) 
  when Def =/= none, In =/= false, Where =/= c ->
    split_optional(Ps, Standard, [P|Opts]);
split_optional([P=#param{def=Def,in=In, where=Where}|Ps], Standard, Opts) 
  when Def =:= none, In =/= false, Where =/= c ->
    split_optional(Ps, [P|Standard], Opts);
split_optional([_|Ps], Standard, Opts) ->
    split_optional(Ps, Standard, Opts);
split_optional([], Standard, Opts) ->
    {reverse(Standard), reverse(Opts)}.

patch_param(P=#param{type=#type{base=Tuple}}, all) when is_tuple(Tuple) ->
    P#param{type={class,ignore}};
patch_param(P=#param{type={merged,_,_,_,_,_,_}}, _) ->
    P#param{type={class,ignore}};
patch_param(P=#param{type=#type{base={class,_}}},_) -> 
    P#param{type={class,ignore}};
patch_param(P=#param{type=#type{base={ref,_}}},_) -> 
    P#param{type={class,ignore}};
patch_param(P,_) -> P.

func_arg_name(#param{def=Def}) when Def =/= none -> skip;
func_arg_name(#param{in=false}) -> skip;
func_arg_name(#param{where=c}) -> skip;
func_arg_name(#param{name=Name}) -> 
    erl_arg_name(Name).

func_arg(#param{def=Def}) when Def =/= none -> skip;
func_arg(#param{in=false}) -> skip;
func_arg(#param{where=c}) -> skip;
func_arg(#param{name=Name,type=#type{base=string}}) -> 
    erl_arg_name(Name);
func_arg(#param{name=Name,type=#type{name="wxArrayString"}}) -> 
    erl_arg_name(Name);
func_arg(#param{name=Name0,type=#type{base={class,_CN}, single=true}}) ->
    Name = erl_arg_name(Name0),
    "#wx_ref{type=" ++ Name ++ "T,ref=" ++ Name++"Ref}";
func_arg(#param{name=Name0,type=#type{base={ref,CN}, single=true}}) ->
    Name = erl_arg_name(Name0),
    "#wx_ref{type=" ++ CN ++ ",ref=" ++ Name++"Ref}";
func_arg(#param{name=Name0,type={merged,_,#type{base={class,_},single=true},_,
				 _, #type{base={class,_},single=true},_}}) ->
    Name = erl_arg_name(Name0),
    "#wx_ref{type=" ++ Name ++ "T,ref=" ++ Name++"Ref}";
func_arg(#param{name=Name,type=#type{base={enum,_}}}) ->
    erl_arg_name(Name);
func_arg(#param{name=Name,type=#type{base={comp,"wxColour",_Tup}, single=true}}) ->
    erl_arg_name(Name);
func_arg(#param{name=Name,type=#type{base={comp,"wxDateTime",_Tup}, single=true}}) ->
    erl_arg_name(Name);
func_arg(#param{name=Name,type=#type{name="wxArtClient", single=true}}) ->
    erl_arg_name(Name);
func_arg(#param{name=Name,type=#type{base={comp,_,Tup}, single=true}}) ->
    N = erl_arg_name(Name),    
    Doc = fun({_,V}) -> erl_arg_name(N)++V end,
    "{" ++ args(Doc, ",", Tup) ++ "}";
func_arg(#param{name=Name}) ->
    erl_arg_name(Name).


guard_test(#param{type=#type{base={class,_},single=true}}) -> skip;
guard_test(#param{def=Def}) when Def =/= none -> skip;
guard_test(#param{where=c})  -> skip;
guard_test(#param{in=In}) when In == false -> skip;
guard_test(#param{name=N, type=#type{base=string}}) ->
    "is_list(" ++ erl_arg_name(N) ++")";
guard_test(#param{name=N, type=#type{name="wxArtClient"}}) ->
    "is_list(" ++ erl_arg_name(N) ++")";
guard_test(#param{name=N, type=#type{name="wxArrayString"}}) ->
    "is_list(" ++ erl_arg_name(N) ++")";
guard_test(#param{name=Name,type=#type{single=Single}}) 
  when Single =/= true->
    "is_list(" ++ erl_arg_name(Name) ++  ")";
guard_test(#param{name=N,type=#type{base=int}}) ->
    "is_integer(" ++ erl_arg_name(N) ++ ")";
guard_test(#param{name=N,type=#type{base=long}}) ->
    "is_integer(" ++ erl_arg_name(N) ++ ")";
guard_test(#param{name=N,type=#type{base=float}}) ->
    "is_float(" ++ erl_arg_name(N) ++ ")";
guard_test(#param{name=N,type=#type{base=double}}) ->
    "is_float(" ++ erl_arg_name(N) ++ ")";
guard_test(#param{name=N,type=#type{base=bool}}) ->
    "is_boolean(" ++ erl_arg_name(N) ++ ")";
guard_test(#param{name=N,type=#type{name="wxDateTime"}}) ->
    "tuple_size(" ++ erl_arg_name(N) ++ ") =:= 2";
guard_test(#param{name=N,type=#type{base=binary}}) ->
    "is_binary(" ++ erl_arg_name(N) ++ ")";
guard_test(#param{name=Name,type=#type{base={enum,_}}}) ->
    "is_integer(" ++ erl_arg_name(Name) ++  ")";
guard_test(#param{name=Name,type=#type{base=eventType}}) ->
    "is_atom(" ++ erl_arg_name(Name) ++  ")";
guard_test(#param{name=_N,type=#type{base={term,_}}}) ->
    skip;
guard_test(#param{name=_N,type=#type{base={ref,_}}}) ->
    skip;
guard_test(#param{name=_N,type=#type{base={class,_}}}) ->
    skip;
guard_test(#param{name=_N,type={merged,_,#type{base={class,_}},_,_,#type{},_}}) ->
    skip;
guard_test(#param{name=N,type=#type{base={comp,"wxColour",_Tup}}}) ->
    "tuple_size(" ++ erl_arg_name(N) ++ ") =:= 3; tuple_size(" ++ erl_arg_name(N) ++ ") =:= 4";
guard_test(#param{name=N,type=#type{base={comp,_,Tup}}}) ->
    Doc = fun({int,V}) -> "is_integer("++erl_arg_name(N)++V ++")";
	     ({double,V}) -> "is_number("++erl_arg_name(N)++V ++")"
	  end,
    args(Doc, ",", Tup);
guard_test(#param{name=N,type={class,ignore}}) ->
    "is_record(" ++ erl_arg_name(N)++ ", wx_ref)";
guard_test(T) -> ?error({unknown_type,T}).

gen_doc(_Class, [#method{method_type=destructor}]) ->  skip;
gen_doc(_Class,[#method{name=N,alias=A,params=Ps,type=T,where=erl_no_opt,method_type=MT}])->
    w("%% @spec (~s~s) -> ~s~n",[doc_arg_types(Ps),"",doc_return_types(T,Ps)]),
    w("%% @equiv ", []),
    gen_function_clause(erl_func_name(N,A),MT,Ps,empty_list,[no_guards,name_only]);
gen_doc(Class,[#method{name=N,params=Ps,type=T}])->
    {_, Optional} = split_optional(Ps),
    NonDef = [Arg || Arg = #param{def=Def,in=In, where=Where} <- Ps, 
		     Def =:= none, In =/= false, Where =/= c],
    OptsType = case Optional of
		   [] -> "";
		   _ when NonDef =:= [] -> "[Option]";
		   _ -> ", [Option]"	       
	       end,
    w("%% @spec (~s~s) -> ~s~n",
      [doc_arg_types(Ps),OptsType,doc_return_types(T,Ps)]),
    doc_optional(Optional, normal),
    DocEnum = doc_enum(T,Ps, normal),   
    case Class of
	"utils" ->
	    w("%% @doc See <a href=\"http://www.wxwidgets.org/manuals/stable/wx_miscellany.html#~s\">"
	      "external documentation</a>.~n", 
	      [lowercase_all(N)]);
	_ ->
	    w("%% @doc See <a href=\"http://www.wxwidgets.org/manuals/stable/wx_~s.html#~s~s\">"
	      "external documentation</a>.~n", 
	      [lowercase_all(Class),lowercase_all(Class),lowercase_all(N)])
    end,
    doc_enum_desc(DocEnum);
gen_doc(Class, Cs = [#method{name=N, alias=A,method_type=MT}|_]) ->
    GetRet  = fun(#method{params=Ps,type=T}) -> 
		      doc_return_types(T,Ps)
	      end,
    GetArgs = fun(#method{params=Ps, where=Where}) -> 
		      Opt = case Where of
				erl_no_opt -> [];
				_ -> 
				    case split_optional(Ps) of
					{_, []} -> [];
					_ ->  ["[Option]"]
				    end
			    end,
		      [doc_arg_type(P) || 
			  P=#param{in=In,def=none,where=W} <- Ps,
			  In =/= false, W =/= c] ++ Opt
	      end,
    Args = zip(lists:map(GetArgs, Cs)),
    Ret  = lists:map(GetRet, Cs),
    w("%% @spec (~s) -> ~s~n",[args(fun doc_arg/1,",",Args),doc_ret(Ret)]),
    case Class of
	"utils" ->
	    w("%% @doc See <a href=\"http://www.wxwidgets.org/manuals/stable/wx_miscellany.html#~s\">"
	      "external documentation</a>.~n", 
	      [lowercase_all(N)]);
	_ ->
	    w("%% @doc See <a href=\"http://www.wxwidgets.org/manuals/stable/wx_~s.html#~s~s\">"
	      "external documentation</a>.~n", 
	      [lowercase_all(Class),lowercase_all(Class),lowercase_all(N)])
    end,
    Name = case MT of constructor -> "new"; _ -> erl_func_name(N,A) end,
    w("%% <br /> Alternatives: ~n",[]),
    [gen_doc2(Name, Clause) || Clause <- Cs], 
    ok.

gen_doc2(Name,#method{params=Ps,where=erl_no_opt,method_type=MT}) ->
    w("%% <p><c>~n",[]),
    w("%% ~s(~s) -> ", [Name,doc_arg_types(Ps)]),
    gen_function_clause(Name,MT,Ps,empty_list,[no_guards,name_only]),
    w(" </c></p>~n",[]);
gen_doc2(Name,#method{params=Ps,type=T}) ->
    {NonDef, Optional} = split_optional(Ps),
    OptsType = case Optional of
		   [] -> "";
		   _ when NonDef =:= [] -> "[Option]";
		   _ -> ", [Option]"	       
	       end,
    w("%% <p><c>~n",[]),
    w("%% ~s(~s~s) -> ~s </c>~n",
      [Name,doc_arg_types(Ps),OptsType,doc_return_types(T,Ps)]),    
    doc_optional(Optional, xhtml),
    DocEnum = doc_enum(T,Ps, xhtml),
    doc_enum_desc(DocEnum),
    w("%% </p>~n",[]).

doc_arg(ArgList) ->
    case all_eq(ArgList) of
	true ->  hd(ArgList);
	false -> 
	    Get = fun(Str) ->
			  [_Name|Types] = string:tokens(Str, ":"),
			  case Types of
			      [Type] -> Type;
			      _ ->
				  "term()"
			  end
		  end,
	    Args0 = lists:map(Get, ArgList),
	    Args = unique(Args0, []),
	    "X::" ++ args(fun(A) -> A end, "|", Args)
    end.

doc_ret(ArgList) ->
    case all_eq(ArgList) of
	true ->  hd(ArgList);
	false -> 
	    args(fun(A) -> A end, "|", ArgList)
    end.

unique([], U) -> reverse(U);
unique([H|R], U) -> 
    case lists:member(H,U) of
	false -> unique(R,[H|U]);
	true  -> unique(R,U)
    end.

all_eq([H|R]) ->  all_eq(R,H).

all_eq([H|R],H) -> all_eq(R,H);
all_eq([],_) -> true;
all_eq(_,_) -> false.

zip(List) ->
    zip(List, [], [], []).

zip([[F|L1]|List], Rest, AccL, Acc) ->
    zip(List, [L1|Rest], [F|AccL], Acc);
zip(Empty, Rest, AccL, Acc) -> 
    true = empty(Empty),
    case empty(Rest) andalso empty(AccL) of
	true -> reverse(Acc);
	false ->
	    zip(reverse(Rest), [], [], [reverse(AccL)|Acc])
    end.

empty([[]|R]) -> empty(R);
empty([]) -> true;
empty(_) -> false.

doc_arg_types(Ps0) ->
    Ps = [P || P=#param{in=In, where=Where} <- Ps0,In =/= false, Where =/= c],
    args(fun doc_arg_type/1, ", ", Ps).
doc_arg_type(#param{name=Name,def=none,type=T}) ->
    erl_arg_name(Name) ++ "::" ++ doc_arg_type2(T);
doc_arg_type(#param{name=Name,in=false,type=T}) ->
    erl_arg_name(Name) ++ "::" ++ doc_arg_type2(T);
doc_arg_type(_) -> skip.

doc_arg_type2(T=#type{single=Single}) when Single =:= array; Single =:= list ->
    "[" ++ doc_arg_type3(T) ++ "]";
doc_arg_type2(T) -> 
    doc_arg_type3(T).

doc_arg_type3(#type{base=string}) -> "string()";
doc_arg_type3(#type{name="wxChar", single=S}) when S =/= true -> "string()";
doc_arg_type3(#type{name="wxArrayString"}) -> "[string()]";
doc_arg_type3(#type{name="wxDateTime"}) ->    "wx:datetime()";
doc_arg_type3(#type{name="wxArtClient"}) ->    "string()";
doc_arg_type3(#type{base=int}) ->        "integer()";
doc_arg_type3(#type{base=long}) ->       "integer()";
doc_arg_type3(#type{base=bool}) ->       "bool()";
doc_arg_type3(#type{base=float}) ->      "float()";
doc_arg_type3(#type{base=double}) ->     "float()";
doc_arg_type3(#type{base=binary}) ->     "binary()";
doc_arg_type3(#type{base={binary,_}}) -> "binary()";
doc_arg_type3(#type{base=eventType}) ->  "atom()";
doc_arg_type3(#type{base={ref,N}}) ->     N++"()";
doc_arg_type3(#type{base={term,_N}}) ->  "term()";
doc_arg_type3(T=#type{base={class,N}}) -> 
    check_class(T),   
    case get(current_class) of
	N -> N ++ "()";
	_ ->  N++":" ++ N++"()"
    end;
doc_arg_type3({merged,_,T1=#type{base={class,N1}},_,_,T2=#type{base={class,N2}},_}) ->
    check_class(T1),
    check_class(T2),
    Curr = get(current_class),
    if 
	N1 =:= Curr, N2 =:= Curr ->  N1++"() | "++ N2++"()";
	N1 =:= Curr -> N1++"() | "++ N2++":" ++ N2++"()";
	N2 =:= Curr -> N1++":" ++ N1++"() | "++ N2++"()";
	true ->
	    N1++":" ++ N1++"() | "++ N2++":" ++ N2++"()"
    end;
doc_arg_type3(#type{base={enum,{_,N}}}) ->    uppercase(N);
doc_arg_type3(#type{base={enum,N}}) ->    uppercase(N);
doc_arg_type3(#type{base={comp,"wxColour",_Tup}}) ->
    "wx:colour()";
doc_arg_type3(#type{base={comp,_,{record,Name}}}) ->
    "wx:" ++ atom_to_list(Name) ++ "()";
doc_arg_type3(#type{base={comp,_,Tup}}) ->
    Doc = fun({int,V}) -> V ++ "::integer()";
	     ({double,V}) -> V ++ "::float()" 
	  end,
    "{" ++ args(Doc, ",", Tup) ++ "}";
doc_arg_type3(T) -> ?error({unknown_type,T}).

doc_return_types(T, Ps) ->
    doc_return_types2(T, [P || P=#param{in=In} <- Ps,In =/= true]).
doc_return_types2(void, []) ->    "ok";
doc_return_types2(void, [#param{type=T}]) ->     doc_arg_type2(T);
doc_return_types2(T, []) ->                      doc_arg_type2(T);
doc_return_types2(void, Ps) -> 
    "{" ++ args(fun doc_arg_type/1,",",Ps) ++ "}";
doc_return_types2(T, Ps) ->
    "{" ++ doc_arg_type2(T) ++ "," ++ args(fun doc_arg_type/1,",",Ps) ++ "}".

break(xhtml) -> "<br />";
break(_) ->     "".

doc_optional([],_) -> ok;
doc_optional(Opts,Type) ->
    w("%%~s Option = ~s~n", [break(Type),args(fun doc_optional2/1, " | ", Opts)]).

doc_optional2(#param{name=Name, def=_Def, type=T}) ->
    "{" ++ erl_option_name(Name) ++ ", " ++ doc_arg_type2(T) ++ "}".

doc_enum(#type{base={enum,Enum}},Ps,Break) ->
    [doc_enum_type(Enum,Break) |
     [doc_enum_type(Type,Break) || #param{type=#type{base={enum,Type}}} <- Ps]];
doc_enum(_,Ps,Break) ->
    [doc_enum_type(Type,Break) || #param{type=#type{base={enum,Type}}} <- Ps].

doc_enum_type(Type,Break) ->
    {Enum0, #enum{vals=Vals}} = wx_gen:get_enum(Type),
    case Enum0 of {_, Enum} -> Enum; Enum -> Enum end,
    Consts = get(consts),
    Format = fun({Name,_What}) ->
		     #const{name=Name} = gb_trees:get(Name, Consts),
		     "?" ++ enum_name(Name)
	     end,
    Vs = args(Format, " | ", Vals),
    w("%%~s ~s = integer()~n", [break(Break),uppercase(Enum)]),
    {uppercase(Enum),Vs}.

doc_enum_desc([]) -> ok;
doc_enum_desc([{Enum,Vs}|R]) ->
    w("%%<br /> ~s is one of ~s~n", [Enum,Vs]),
    doc_enum_desc(R).

%% Misc functions prefixed with wx
erl_func_name("wx" ++ Name, undefined) ->   check_name(lowercase(Name));  
erl_func_name(Name, undefined) ->   check_name(lowercase(Name));
erl_func_name(_, Alias) -> check_name(lowercase(Alias)).

erl_option_name(Name) -> lowercase(Name).
erl_arg_name(Name) ->    uppercase(Name).

check_name("destroy") -> "'Destroy'";
check_name("xor") -> "'Xor'";
check_name("~" ++ _Name) -> "destroy";
check_name(Name) -> Name.

marshal_opts([], _,_) -> "";     %% No opts skip this!
marshal_opts(Opts, Align, Args) ->
    w("  MOpts = fun", []), 
    marshal_opts1(Opts,1),
    w(";~n          (BadOpt, _) -> erlang:error({badoption, BadOpt}) end,~n", []),
    w("  BinOpt = list_to_binary(lists:foldl(MOpts, [<<0:32>>], Options)),~n", []),
    {Str, _} = align(64, Align, "BinOpt/binary"),
    case Args of
	[] -> Str;   % All Args are optional
	_ ->    ", " ++ Str
    end.
    
marshal_opts1([P],N) ->
    marshal_opt(P,N);
marshal_opts1([P|R],N) ->
    marshal_opt(P,N),
    w(";~n          ", []),
    marshal_opts1(R,N+1).

marshal_opt(P0=#param{name=Name,type=Type},N) ->
    P = P0#param{def=none},
    {Arg,Align} = marshal_arg(Type,erl_arg_name(Name),1),
    AStr = if Align =:= 0 -> "";
	      Align =:= 1 -> ",0:32"
	   end,	
    w("({~s, ~s}, Acc) -> ", [erl_option_name(Name), func_arg(P)]), 
    arg_type_test(P,"",[]),
    case Arg of
	skip -> 
	    w("[<<~p:32/?UI~s>>|Acc]", [N, AStr]);
	_ -> 
	    w("[<<~p:32/?UI,~s~s>>|Acc]", [N, Arg,AStr])
    end.   
marshal_args(Ps) ->
    marshal_args(Ps, [], 0).

marshal_args([#param{where=erl}|Ps], Margs, Align) ->
    marshal_args(Ps, Margs, Align);
marshal_args([#param{name=_N,where=c}|Ps], Margs, Align) ->
    %% io:format("~p:~p: skip ~p~n",[get(current_class),get(current_func),_N]),
    marshal_args(Ps, Margs, Align);
marshal_args([#param{in=false}|Ps], Margs, Align) ->
    marshal_args(Ps, Margs, Align);
marshal_args([#param{def=Def}|Ps], Margs, Align) when Def =/= none ->
    marshal_args(Ps, Margs, Align);
marshal_args([#param{name=Name, type=Type}|Ps], Margs, Align0) ->
    {Arg,Align} = marshal_arg(Type,erl_arg_name(Name),Align0),
    marshal_args(Ps, [Arg|Margs], Align);
marshal_args([],Margs, Align) ->
    {args(fun(Str) -> Str end, ",", reverse(Margs)), Align}.

marshal_arg(#type{base={class,_}, single=true}, Name, Align) ->
    align(32, Align, Name ++ "Ref:32/?UI");
marshal_arg({merged,_,#type{base={class,_},single=true},_,_,_,_},Name,Align) ->
    align(32, Align, Name ++ "Ref:32/?UI");
marshal_arg(#type{base={ref,_}, single=true}, Name, Align) ->
    align(32, Align, Name ++ "Ref:32/?UI");
marshal_arg(#type{single=true,base=long}, Name, Align) ->
    align(64, Align, Name ++ ":64/?UI");
marshal_arg(#type{single=true,base=float}, Name, Align) ->
    align(32, Align, Name ++ ":32/?F");
marshal_arg(#type{single=true,base=double}, Name, Align) ->
    align(64, Align, Name ++ ":64/?F");
marshal_arg(#type{single=true,base=int}, Name, Align) ->
    align(32, Align, Name ++ ":32/?UI");
marshal_arg(#type{single=true,base={enum,_Enum}}, Name, Align) ->
    align(32, Align, Name ++ ":32/?UI");

marshal_arg(#type{single=true,base=bool}, Name, Align) ->
    align(32, Align, "(wxe_util:from_bool(" ++ Name ++ ")):32/?UI");
marshal_arg(#type{name="wxChar", single=Single}, Name, Align0)  
  when Single =/= true ->
    {Str,Align} = 
	align(32,Align0, "(byte_size("++Name++"_UC)):32/?UI,(" ++ Name ++ "_UC)/binary"),
    MsgSize = "(" ++ integer_to_list(Align*4)++"+byte_size("++Name++"_UC))",
    {Str++", 0:(((8- (" ++ MsgSize ++" band 16#7)) band 16#7))/unit:8",0};
marshal_arg(#type{base=string}, Name, Align0) ->
    {Str,Align} = 
	align(32,Align0, "(byte_size("++Name++"_UC)):32/?UI,(" ++ Name ++ "_UC)/binary"),
    MsgSize = "(" ++ integer_to_list(Align*4)++"+byte_size("++Name++"_UC))",
    {Str++", 0:(((8- (" ++ MsgSize ++" band 16#7)) band 16#7))/unit:8",0};
marshal_arg(#type{name="wxArrayString"}, Name, Align0) ->
    InnerBin  = "<<(byte_size(UC_Str)):32/?UI, UC_Str/binary>>", 
    Outer =  "(<< " ++ InnerBin ++ "|| UC_Str <- "++ Name ++"_UCA>>)/binary",
    Str0  =  "(length("++Name++"_UCA)):32/?UI, " ++ Outer,
    {Str,Align} = align(32,Align0,Str0),
    MsgSize = "("++integer_to_list(Align*4) ++ 
	" + lists:sum([byte_size(S)+4||S<-" ++ Name ++"_UCA]))",
    AStr = ", 0:(((8- (" ++ MsgSize ++" band 16#7)) band 16#7))/unit:8",
    {Str ++ AStr, 0};
marshal_arg(#type{single=true,base={comp,"wxColour",_Comp}}, Name, Align0) ->
    Str = "(wxe_util:colour_bin(" ++ Name ++ ")):16/binary",
    {Str,Align0};
marshal_arg(#type{single=true,base={comp,"wxDateTime",_Comp}}, Name, Align) ->
    {"(wxe_util:datetime_bin(" ++ Name ++ ")):24/binary", Align};
marshal_arg(#type{single=true,base={comp,_,Comp}}, Name, Align0) ->
    case hd(Comp) of
	{int,_} ->
	    A = [Name++Spec++":32/?UI" || {int,Spec} <- Comp],
	    Str = args(fun(Str) -> Str end, ",", A),
	    {Str,(Align0 + length(Comp)) rem 2};
	{double,_} ->
	    A = [Name++Spec++":64/float" || {double,Spec} <- Comp],
	    Str = args(fun(Str) -> Str end, ",", A),
	    align(64,Align0,Str)
    end;
marshal_arg(#type{base={term,_}}, _Name, Align0) ->
    {skip,Align0};
marshal_arg(#type{base=binary}, _Name, Align0) ->
    {skip,Align0};
marshal_arg(#type{base=Base, single=Single}, Name, Align0) 
  when Single =/= true ->
    case Base of 
	int -> 
	    Str0 = "(length("++Name++")):32/?UI,\n"
		"        (<< <<C:32/?I>> || C <- "++Name++">>)/binary",
	    {Str,Align} = align(32,Align0, Str0),
	    {Str ++ ", 0:((("++integer_to_list(Align)++"+length("++Name++ ")) rem 2)*32)", 0};
	{ObjRef,_} when ObjRef =:= class; ObjRef =:= ref -> 
	    Str0 = "(length("++Name++")):32/?UI,",
	    Str1 = "\n     (<< <<(C#wx_ref.ref):32/?UI>> || C <- "++Name++">>)/binary",
	    {Str2,Align} = align(32, Align0, Str1),
	    AlignStr = ", 0:((("++integer_to_list(Align)++"+length("++Name++ ")) rem 2)*32)",
	    {Str0 ++ Str2 ++ AlignStr, 0};
	{comp, "wxPoint", _} ->
	    Str0 = "(length("++Name++")):32/?UI,\n"
		"        (<< <<X:32/?I,Y:32/?I>> || {X,Y} <- "++Name++">>)/binary",
	    align(32,Align0, Str0);
	double ->
	    Str0 = "(length("++Name++")):32/?UI,\n",
	    Str1 = "  (<< <<C:64/float>> || C <- "++Name++">>)/binary",
	    {Str,_Align} = align(64,Align0+1, Str1),
	    {Str0 ++ Str, 0};
	_ ->
	    ?error({unhandled_array_type, Base})
    end;
marshal_arg(T=#type{name=_wxString}, Name, _Align) ->
    ?error({unhandled_type, {Name,T}}).


align(32, 0, Str) -> {Str, 1};
align(32, 1, Str) -> {Str, 0};
align(64, 0, Str) -> {Str, 0};
align(64, 1, Str) -> {"0:32," ++ Str,0};
align(Sz, W, Str) -> align(Sz, W rem 2, Str).

enum_name(Name) -> 
    case string:tokens(Name, ":") of
	[Name] -> Name;
	[C,N] ->  C ++ "_" ++ N
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

gen_enums_ints() ->
    %% open_write("../include/wx.hrl"), opened in gen_event_recs
    w("~n%% Hardcoded Records ~n", []),
    w("-record(wxMouseState, {x, y,  %% integer() ~n"
      "          leftDown, middleDown, rightDown, %% bool() ~n"
      "          controlDown, shiftDown, altDown, metaDown, cmdDown %% bool()~n"
      "        }).~n", []),
    w("-record(wxHtmlLinkInfo, { ~n"
      "          href, target %% string() ~n"
      "        }).~n", []),
    w("~n%% Hardcoded Defines ~n", []),
    Enums = [E || E = {{enum,_},#enum{as_atom=false}} <- get()],
    w("-define(wxDefaultSize, {-1,-1}).~n", []), 
    w("-define(wxDefaultPosition, {-1,-1}).~n", []), 
    w("~n%% Global Variables ~n", []),
    [w("-define(~s,  wxe_util:get_const(~s)).~n", [Gvar, Gvar]) || 
	{Gvar,_,_Id} <- get(gvars)],
    w("~n%% Enum and defines ~n", []),
    foldl(fun({{enum,Type},Enum= #enum{as_atom=false}}, Done) ->
		  build_enum_ints(Type,Enum,Done);
	     (_,Done) -> Done
	  end, gb_sets:empty(), lists:sort(Enums)),
    close().

build_enum_ints(Type,#enum{vals=Vals},Done) ->
    case Type of
	[$@|_] ->  ok; % anonymous
	{Class,[$@|_]} when Vals =/= [] ->  w("% From class ~s ~n", [Class]);
	{Class,Enum} when Vals =/= [] ->  w("% From ~s::~s ~n", [Class,Enum]);
	_ when Vals =/= [] ->  w("% Type ~s ~n", [Type]);
	_ -> ok
    end,
    
    Format = fun(#const{name=Name,val=Value,is_const=true}) when is_integer(Value) ->		     
		     w("-define(~s, ~p).~n", [enum_name(Name),Value]);
		(#const{name=Name,val=Value,is_const=false}) when is_integer(Value) ->
		     w("-define(~s, wxe_util:get_const(~s)).~n", [enum_name(Name),enum_name(Name)]);
		(#const{name=Name,val={Str,0}}) ->
		     case string:tokens(Str, " |()") of
			 [Token] ->
			     w("-define(~s, ?~s).~n", [enum_name(Name),Token]);
			 Tokens ->
			     Def = args(fun(T) -> [$?|T] end, " bor ", Tokens),
			     w("-define(~s, (~s)).~n", [enum_name(Name),Def])
		     end;
		(#const{name=Name,val={Str,N}}) ->
		     case string:tokens(Str, " |()") of
			 [Token] ->
			     w("-define(~s, (?~s+~p)).~n", [enum_name(Name),Token,N])
		     end
	     end,
    Consts = get(consts),
    Write = fun({Name,_What}, Skip) ->
		    case gb_sets:is_member(Name,Skip) of
			true -> 
			    Skip;
			false ->
			    case gb_trees:lookup(Name, Consts) of
				{value, Const} ->
				    Format(Const), 
				    gb_sets:add(Name,Skip);
				none -> Skip
			    end
		    end
	    end,
    lists:foldl(Write, Done, Vals).

gen_event_recs() ->
    open_write("../include/wx.hrl"),
    erl_copyright(),
    w("", []),
    w("%% This file is generated DO NOT EDIT~n~n", []),
    w("%%  All event messages are encapsulated in a wx record ~n"
      "%%  they contain the widget id and a specialized event record.~n" 
      "%%  Each event record may be sent for one or more event types.~n" 
      "%%  The mapping to wxWidgets is one record per class.~n~n",[]),
    w("%% @type wx() = #wx{id=integer(), obj=wx:wxObject(), userData=term(), event=Rec}. Rec is a event record.~n",[]),
    w("-record(wx, {id,     %% Integer Identity of object.~n"
      "             obj,    %% Object reference that was used in the connect call.~n"
      "             userData, %% User data specified in the connect call.~n"
      "             event}).%% The event record ~n~n",[]),
    w("%% Here comes the definitions of all event records.~n"
      "%% they contain the event type and possible some extra information.~n~n",[]),
    Types = [build_event_rec(C) || {_,C=#class{event=Evs}} <- get(), Evs =/= false],
    w("%% @type wxEventType() = ~s.~n", 
      [args(fun(Ev) -> Ev end, " | ", lists:sort(lists:append(Types)))]),
    %% close(), closed in gen_enums_ints
    ok.

find_inherited_attr(Param = {PName,_}, Name) ->
    #class{parent=Parent, attributes=Attrs} = get({class, Name}),
    case lists:keysearch(atom_to_list(PName), #param.name, Attrs) of
	{value, P=#param{}} ->
	    P;
	_ ->
	    find_inherited_attr(Param, Parent)
    end.

filter_attrs(#class{name=Name, parent=Parent,attributes=Attrs}) ->
    Attr1 = lists:foldl(fun(#param{acc=skip},Acc) -> Acc; 
			   (P=#param{prot=public},Acc) -> [P|Acc];
			   (#param{acc=undefined},Acc) -> Acc; 
			   ({inherited, PName},Acc) ->
				case find_inherited_attr(PName, Parent) of
				    undefined -> 
					io:format("~p:~p: Missing Event Attr ~p in ~p~n",
						  [?MODULE,?LINE, PName, Name]),
					Acc;
				    P -> 
					[P|Acc]
				end;
			   (P, Acc) -> [P|Acc]
			end, [], Attrs),
    lists:reverse(Attr1).
   
build_event_rec(Class=#class{name=Name, event=Evs}) ->
    EvTypes = [event_type_name(Ev) || Ev <- Evs],
    Str  = args(fun(Ev) -> "<em>"++Ev++"</em>" end, ", ", EvTypes),
    Attr = filter_attrs(Class),
    Rec = event_rec_name(Name),
    GetName = fun(#param{name=N}) ->event_attr_name(N) end,
    GetType = fun(#param{name=N,type=T}) ->
		      event_attr_name(N) ++ "=" ++ doc_arg_type2(T) 
	      end,
    case Attr =:= [] of
	true -> 
	    w("%% @type ~s() = #~s{type=wxEventType()}.~n", [Rec,Rec]),
	    w("%% <dl><dt>EventType:</dt> <dd>~s</dd></dl>~n",[Str]),
%% 	    case is_command_event(Name) of 
%% 		true  -> w("%% This event skips other event handlers.~n",[]);
%% 		false -> w("%% This event will be handled by other handlers~n",[])
%% 	    end,
	    w("%% Callback event: {@link ~s}~n", [Name]),
	    w("-record(~s, {type}). ~n~n", [Rec]);
	false ->
	    w("%% @type ~s() = #~s{type=wxEventType(),~s}.~n", 
	      [Rec,Rec,args(GetType,",",Attr)]),
	    w("%% <dl><dt>EventType:</dt> <dd>~s</dd></dl>~n",[Str]),
%% 	    case is_command_event(Name) of 
%% 		true -> w("%% This event skips other event handlers.~n",[]);
%% 		false -> w("%% This event will be handled by other handlers~n",[])
%% 	    end,	    
	    w("%% Callback event: {@link ~s}~n", [Name]),
	    w("-record(~s,{type, ~s}). ~n~n", [Rec,args(GetName,",",Attr)])
    end,
    EvTypes.

is_command_event(Name) ->
    case lists:member("wxCommandEvent", parents(Name)) of
	true -> true;
	false -> false
    end.
	    
event_rec_name(Name0 = "wx" ++ _) ->
    "tnevE" ++ Name1 = reverse(Name0),
    reverse(Name1).

event_type_name({EvN,_,_}) -> event_type_name(EvN);
event_type_name({EvN,_}) -> event_type_name(EvN);
event_type_name(EvN) ->
    "wxEVT_" ++ Ev = atom_to_list(EvN),
    lowercase_all(Ev).

event_attr_name("m_" ++ Attr) ->
    lowercase(Attr);
event_attr_name(Attr) ->
    lowercase(Attr).


gen_funcnames() -> 
    open_write("../src/gen/wxe_debug.hrl"),
    erl_copyright(),
    w("%% This file is generated DO NOT EDIT~n~n", []),
    w("wxdebug_table() -> ~n[~n", []),
    w(" {0, {wx, internal_batch_start, 0}},~n", []),
    w(" {1, {wx, internal_batch_end, 0}},~n", []),
    w(" {4, {wxObject, internal_destroy, 1}},~n", []),
    Ns = get_unique_names(),
    [w(" {~p, {~s, ~s, ~p}},~n", [Id,Class,erl_func_name(Name,undefined),A]) || {Class,Name,A,Id} <- Ns],
    w(" {-1, {mod, func, -1}}~n",[]),
    w("].~n~n", []),
    close(),
    open_write("../src/gen/wxe_funcs.hrl"),
    erl_copyright(),
    w("%% This file is generated DO NOT EDIT~n~n", []),
    w("%% We define each id so we don't get huge diffs when adding new funcs/classes~n~n",[]),
    [w("-define(~s_~s, ~p).~n", [Class,Name,Id]) || {Class,Name,_,Id} <- Ns],
    close().

get_unique_name(ID) when is_integer(ID) ->
    Tree =  get(unique_names),
    {Class,Name, _,_} = gb_trees:get(ID, Tree),
    Class ++ "_" ++ Name.

get_unique_names() ->
    Tree =  get(unique_names),
    gb_trees:values(Tree).

gen_unique_names(Defs) ->
    Names = [ unique_names(Ms, Class) || #class{name=Class, methods=Ms} <- Defs],
    Data =  [{Id, Struct} || Struct = {_,_,_,Id} <- lists:append(Names)],
    Tree = gb_trees:from_orddict(lists:sort(Data)),
    put(unique_names, Tree).

unique_names(Ms0, Class) ->
    Ms1 = [M || M = #method{where = W} <- lists:append(Ms0),
		W =/= erl_no_opt],
    Ms2 = lists:keysort(#method.name, Ms1),
    Ms  = split_list(fun(#method{name=N}, M) -> {N =:= M, N} end, undefined, Ms2),
    unique_names2(Ms,Class).
%% by Names
unique_names2([[#method{id=Id, name=Method,alias=Alias, max_arity=A}]|Ms], Class) -> 
    [{Class,uname(alias(Method,Alias),Class),A,Id} | unique_names2(Ms,Class)];
unique_names2([Ms0|RMs], Class) ->
    Split = fun(#method{max_arity=A}, P) -> {A =:= P, A} end,
    Ms = split_list(Split, 0, Ms0),
    unique_names3(Ms, Class) ++ unique_names2(RMs, Class);
unique_names2([], _Class) -> [].
%% by Arity
unique_names3([[#method{id=Id, name=Method,alias=Alias, max_arity=A}]|Ms], Class) ->
    [{Class,uname(alias(Method,Alias),Class) ++ "_" ++ integer_to_list(A),A,Id} | unique_names3(Ms,Class)];
unique_names3([Ms0|RMs], Class) ->
    unique_names4(Ms0, 0, Class) ++ unique_names3(RMs, Class);
unique_names3([], _Class) -> [].

unique_names4([#method{id=Id, name=Method,alias=Alias, max_arity=A}|Ms], C, Class) ->
    [{Class,uname(alias(Method,Alias),Class) ++ "_" ++ integer_to_list(A) ++ "_" ++ integer_to_list(C),A,Id}
     | unique_names4(Ms,C+1,Class)];
unique_names4([], _, _Class) -> [].

alias(Method, undefined) -> Method;
alias(_, Alias) -> Alias.
     
uname(Class,Class) ->   "new";
uname([$~ | _], _  ) -> "destruct";
uname(Name, _) -> Name.
       
split_list(F, Keep, List) ->
    split_list(F, Keep, List, []).

split_list(F, Keep, [M|Ms], Acc) ->
    case F(M,Keep) of
	{true, Test} ->
	    split_list(F, Test, Ms, [M|Acc]);
	{false, Test} when Acc =:= [] ->
	    split_list(F, Test, Ms, [M]);
	{false, Test} ->
	    [lists:reverse(Acc)|split_list(F, Test, Ms, [M])]
    end;
split_list(_, _, [], []) -> [];
split_list(_, _, [], Acc) -> [lists:reverse(Acc)].
   

