-module(guidestar).

-export([start/0, advanced_search/2]).

-record(guidestar, {server, version, key}).
-record(request, {method, path, params, conn, headers, body}).

start() ->
  [ensure_started(X) || X <- [crypto, public_key, asn1, ssl, idna, hackney]].

ensure_deps_started() ->
  {ok, Deps} = application:get_key(guidestar, applications),
  true = lists:all(fun ensure_started/1, Deps).

ensure_started(App) ->
  case application:start(App) of
    ok ->
      true;
    {error, {already_started, App}} ->
      true;
    Else ->
      error_logger:error_msg("Couldn't start ~p: ~p", [App, Else]),
      Else
  end.

advanced_search(Query, Conn) ->
  Request = #request{
    method = get,
    path = <<"advancedsearch">>,
    params = [{"q", edoc_lib:escape_uri(Query)}, {"r", "25"}],
    conn = Conn,
    headers = [],
    body = <<>>
  },
  fetch(Request).

fetch(Request) ->
  Resp = do_request(Request),
  {<<"total_hits">>, Total} = proplists:lookup(<<"total_hits">>, Resp),
  {<<"hits">>, Results} = proplists:lookup(<<"hits">>, Resp),
  fetch_remaining(Total, length(Results), 1, Request, Results).

fetch_remaining(Total, Count, _, _, Results) when Count >= Total ->
  Results;

fetch_remaining(Total, Count, Page, Request, Results) ->
  io:format("FETCH -- TOTAL: ~w COUNT: ~w~n", [Total, Count]),
  Params = lists:keystore("p", 1, Request#request.params, {"p", Page}),
  Request1 = Request#request{ params = Params },
  Resp = do_request(Request1),
  {<<"hits">>, Results1} = proplists:lookup(<<"hits">>, Resp),
  Results2 = Results ++ Results1,
  fetch_remaining(Total, length(Results2), Page + 1, Request1, Results2).

do_request(#request{method = Method, path = Path, params = Params, conn = Conn,
    headers = Headers, body = Body}) ->
  Url = url(Path, Params, Conn),
  Options = [ {ssl_options, [{ versions, [sslv3] }]}],
  {ok, Status, _Headers, Client} = hackney:request(Method, Url, Headers, Body, Options),
  case Status of
    Status when Status =:= 404 ->
      throw(not_found);
    Status when Status =:= 401 ->
      throw(not_authorized);
    Status when Status =:= 403 ->
      throw(forbidden);
    Status when Status =< 399 ->
      {ok, ResBody} = hackney:body(Client),
      {Result} = jiffy:decode(ResBody), Result;
    Status when Status > 399 ->
      error
  end.

url(Path, Params, #guidestar{ server = S, version = V, key = K }) ->
  iolist_to_binary(["https://", K, "@", S, "/v", V, "/", Path,
    "?", params_to_string(Params)]).

params_to_string(Params) ->
  join("&", [join("=", [K, V]) || {K, V} <- Params]).

join(Sep, Xs) ->
  lists:concat(intersperse(Sep, Xs)).

intersperse(_, []) -> [];
intersperse(_, [X]) -> [X];
intersperse(Sep, [X|Xs]) ->
  [X, Sep|intersperse(Sep, Xs)].
