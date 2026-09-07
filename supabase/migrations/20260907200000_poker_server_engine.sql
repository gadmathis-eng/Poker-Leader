-- Pot Master — the server owns the hand.
--
-- Paste this whole file into the Supabase SQL Editor and click Run, after
-- 20260907190000_open_tables_lockdown.sql. It is safe to run more than once.
--
-- Until now the phones dealt the cards, decided whose turn it was, named a
-- winner, and handed `vault_record_hand` a list of chip deltas. A modified
-- client could therefore decide who won money. This migration moves every
-- authoritative decision into Postgres:
--
--   * The server creates the hand, picks the active seats from the Vault
--     stakes, shuffles the deck, and deals.
--   * Clients may only request check / call / bet / raise / fold / all-in.
--   * The server verifies the turn, the move, and the player's remaining chips.
--   * The pot is the sum of committed chips the server recorded. Leaving folds
--     the player and leaves those chips in the pot.
--   * Showdown (or a fold-out) is evaluated here, side pots included, and the
--     Vault is posted from that result. `vault_record_hand` no longer accepts
--     a client-supplied winner.
--   * Hole cards live in a table with no client grants. A player can only see
--     their own, until the server turns them over at showdown.

-- ---------------------------------------------------------------------------
-- Tables. Nobody sitting at a table is granted these.
-- ---------------------------------------------------------------------------

create table if not exists public.poker_hands (
    id uuid primary key default gen_random_uuid(),
    invite_code text not null,
    hand_number integer not null check (hand_number >= 1),
    revision integer not null default 1 check (revision >= 1),
    dealer_seat integer not null,
    ante_cents bigint not null default 0 check (ante_cents >= 0),
    street text not null default 'preflop'
        check (street in ('preflop', 'flop', 'turn', 'river', 'showdown')),
    board jsonb not null default '[]'::jsonb,
    deck jsonb not null default '[]'::jsonb,
    acting_seat integer,
    is_complete boolean not null default false,
    is_revealed boolean not null default false,
    is_settled boolean not null default false,
    winner_seats integer[] not null default '{}',
    result_summary text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists poker_hands_invite_live_idx
    on public.poker_hands (invite_code)
    where not is_complete;

create unique index if not exists poker_hands_invite_number_idx
    on public.poker_hands (invite_code, hand_number);

create table if not exists public.poker_hand_seats (
    id uuid primary key default gen_random_uuid(),
    hand_id uuid not null references public.poker_hands (id) on delete cascade,
    user_id uuid not null,
    player_key text not null,
    seat_number integer not null check (seat_number between 1 and 8),
    player_name text not null default 'Player',
    stack_cents bigint not null check (stack_cents >= 0),
    committed_cents bigint not null default 0 check (committed_cents >= 0),
    street_committed_cents bigint not null default 0 check (street_committed_cents >= 0),
    has_acted boolean not null default false,
    is_folded boolean not null default false,
    hole_cards jsonb not null default '[]'::jsonb,
    awarded_cents bigint not null default 0 check (awarded_cents >= 0),
    topped_up_cents bigint not null default 0 check (topped_up_cents >= 0),
    hand_summary text,
    last_action_id text,
    unique (hand_id, player_key),
    unique (hand_id, seat_number)
);

create index if not exists poker_hand_seats_hand_idx
    on public.poker_hand_seats (hand_id);

create table if not exists public.poker_hand_actions (
    id uuid primary key default gen_random_uuid(),
    hand_id uuid not null references public.poker_hands (id) on delete cascade,
    action_id text not null,
    player_key text not null,
    action text not null,
    amount_cents bigint,
    revision integer not null,
    created_at timestamptz not null default now(),
    unique (hand_id, action_id)
);

create index if not exists poker_hand_actions_hand_idx
    on public.poker_hand_actions (hand_id);

alter table public.poker_hands enable row level security;
alter table public.poker_hand_seats enable row level security;
alter table public.poker_hand_actions enable row level security;

revoke all on table public.poker_hands from public, anon, authenticated;
revoke all on table public.poker_hand_seats from public, anon, authenticated;
revoke all on table public.poker_hand_actions from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Cards and ranking. Same rules as PokerHandEvaluator.swift.
-- ---------------------------------------------------------------------------

create or replace function public.poker_card_rank(p_code text)
returns integer
language sql
immutable
as $$
    select case upper(left(p_code, 1))
        when 'A' then 14
        when 'K' then 13
        when 'Q' then 12
        when 'J' then 11
        when 'T' then 10
        else nullif(upper(left(p_code, 1)), '')::integer
    end;
$$;

create or replace function public.poker_card_suit(p_code text)
returns text
language sql
immutable
as $$
    select lower(right(p_code, 1));
$$;

create or replace function public.poker_rank_name(p_rank integer, p_plural boolean default false)
returns text
language sql
immutable
as $$
    select case p_rank
        when 14 then case when p_plural then 'aces' else 'ace' end
        when 13 then case when p_plural then 'kings' else 'king' end
        when 12 then case when p_plural then 'queens' else 'queen' end
        when 11 then case when p_plural then 'jacks' else 'jack' end
        when 10 then case when p_plural then 'tens' else 'ten' end
        when 9 then case when p_plural then 'nines' else 'nine' end
        when 8 then case when p_plural then 'eights' else 'eight' end
        when 7 then case when p_plural then 'sevens' else 'seven' end
        when 6 then case when p_plural then 'sixes' else 'six' end
        when 5 then case when p_plural then 'fives' else 'five' end
        when 4 then case when p_plural then 'fours' else 'four' end
        when 3 then case when p_plural then 'threes' else 'three' end
        else case when p_plural then 'twos' else 'two' end
    end;
$$;

create or replace function public.poker_full_deck()
returns jsonb
language sql
immutable
as $$
    select jsonb_agg(r.sym || s.suit order by s.ord, r.rank)
    from (values (1,'s'), (2,'h'), (3,'d'), (4,'c')) as s(ord, suit)
    cross join (
        values (2,'2'),(3,'3'),(4,'4'),(5,'5'),(6,'6'),(7,'7'),
               (8,'8'),(9,'9'),(10,'T'),(11,'J'),(12,'Q'),(13,'K'),(14,'A')
    ) as r(rank, sym);
$$;

create or replace function public.poker_shuffle_deck(p_deck jsonb)
returns jsonb
language sql
volatile
as $$
    select coalesce(jsonb_agg(card order by gen_random_uuid()), '[]'::jsonb)
    from jsonb_array_elements_text(coalesce(p_deck, '[]'::jsonb)) as card;
$$;

create or replace function public.poker_cents_text(p_cents bigint)
returns text
language sql
immutable
as $$
    select coalesce(
        trim(trailing '.' from trim(trailing '0' from (coalesce(p_cents, 0)::numeric / 100)::text)),
        '0'
    );
$$;

create or replace function public.poker_ante_cents(p_text text)
returns bigint
language sql
immutable
as $$
    select greatest(0, round(coalesce(nullif(trim(p_text), '')::numeric, 0) * 100)::bigint);
$$;

-- Rank of exactly five cards. Returns
-- {category, tiebreakers, cards, summary} or null.
create or replace function public.poker_rank_five(p_cards jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
    codes text[];
    ranks int[];
    suits text[];
    i int;
    j int;
    is_flush boolean;
    straight_high int;
    wheel boolean := false;
    unique_ranks int;
    high int;
    low int;
    groups jsonb := '[]'::jsonb;
    grp jsonb;
    counts int[];
    tiebreakers int[] := '{}';
    category int;
    summary text;
    ordered text[];
    r int;
    c int;
    leftover text[];
begin
    if jsonb_array_length(coalesce(p_cards, '[]'::jsonb)) <> 5 then
        return null;
    end if;

    select array_agg(card) into codes
    from jsonb_array_elements_text(p_cards) as card;

    ranks := array(
        select public.poker_card_rank(c) from unnest(codes) as c
    );
    suits := array(
        select public.poker_card_suit(c) from unnest(codes) as c
    );

    if ranks @> array[null::int] or array_position(ranks, null) is not null then
        return null;
    end if;

    -- Sort cards by rank descending.
    select array_agg(card order by public.poker_card_rank(card) desc)
    into codes
    from unnest(codes) as card;
    ranks := array(select public.poker_card_rank(c) from unnest(codes) as c);

    is_flush := (select count(distinct s) = 1 from unnest(suits) as s);
    unique_ranks := (select count(distinct r) from unnest(ranks) as r);
    high := ranks[1];
    low := ranks[5];

    straight_high := null;
    if unique_ranks = 5 then
        if high - low = 4 then
            straight_high := high;
        elsif ranks[1] = 14 and ranks[2] = 5 and ranks[3] = 4
           and ranks[4] = 3 and ranks[5] = 2 then
            straight_high := 5;
            wheel := true;
        end if;
    end if;

    if wheel then
        ordered := array(
            select c from unnest(codes) as c
            where public.poker_card_rank(c) <> 14
            order by public.poker_card_rank(c) desc
        ) || array(
            select c from unnest(codes) as c
            where public.poker_card_rank(c) = 14
        );
    else
        ordered := codes;
    end if;

    if straight_high is not null then
        category := case when is_flush then 9 else 5 end;
        if category = 9 and straight_high = 14 then
            summary := 'Royal flush';
        elsif category = 9 then
            summary := 'Straight flush, ' || public.poker_rank_name(straight_high) || ' high';
        else
            summary := 'Straight, ' || public.poker_rank_name(straight_high) || ' high';
        end if;
        return jsonb_build_object(
            'category', category,
            'tiebreakers', jsonb_build_array(straight_high),
            'cards', to_jsonb(ordered),
            'summary', summary
        );
    end if;

    if is_flush then
        return jsonb_build_object(
            'category', 6,
            'tiebreakers', to_jsonb(ranks),
            'cards', to_jsonb(codes),
            'summary', 'Flush, ' || public.poker_rank_name(ranks[1]) || ' high'
        );
    end if;

    for r, c in
        select public.poker_card_rank(card) as rk, count(*)::int
        from unnest(codes) as card
        group by 1
        order by 2 desc, 1 desc
    loop
        leftover := array(
            select card from unnest(codes) as card
            where public.poker_card_rank(card) = r
        );
        groups := groups || jsonb_build_array(
            jsonb_build_object('rank', r, 'count', c, 'cards', to_jsonb(leftover))
        );
        tiebreakers := tiebreakers || r;
        counts := coalesce(counts, '{}') || c;
    end loop;

    ordered := array(
        select jsonb_array_elements_text(g->'cards')
        from jsonb_array_elements(groups) as g
    );

    if counts = array[4, 1] then
        category := 8;
        summary := 'Four of a kind, ' || public.poker_rank_name(tiebreakers[1], true);
    elsif counts = array[3, 2] then
        category := 7;
        summary := 'Full house, ' || public.poker_rank_name(tiebreakers[1], true)
            || ' full of ' || public.poker_rank_name(tiebreakers[2], true);
    elsif counts = array[3, 1, 1] then
        category := 4;
        summary := 'Three of a kind, ' || public.poker_rank_name(tiebreakers[1], true);
    elsif counts = array[2, 2, 1] then
        category := 3;
        summary := 'Two pair, ' || public.poker_rank_name(tiebreakers[1], true)
            || ' and ' || public.poker_rank_name(tiebreakers[2], true);
    elsif counts = array[2, 1, 1, 1] then
        category := 2;
        summary := 'Pair of ' || public.poker_rank_name(tiebreakers[1], true);
    else
        category := 1;
        summary := initcap(public.poker_rank_name(tiebreakers[1])) || ' high';
    end if;

    return jsonb_build_object(
        'category', category,
        'tiebreakers', to_jsonb(tiebreakers),
        'cards', to_jsonb(ordered),
        'summary', summary
    );
end;
$$;

-- Best five-card hand from two hole cards plus the board.
create or replace function public.poker_best_hand(p_cards jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
    n int;
    uniq jsonb;
    best jsonb;
    candidate jsonb;
    i int; j int; k int; l int; m int;
    pick jsonb;
    cards text[];
begin
    select coalesce(jsonb_agg(distinct card), '[]'::jsonb) into uniq
    from jsonb_array_elements_text(coalesce(p_cards, '[]'::jsonb)) as card;

    n := jsonb_array_length(uniq);
    if n < 5 then
        return null;
    end if;
    if n = 5 then
        return public.poker_rank_five(uniq);
    end if;

    select array_agg(card) into cards
    from jsonb_array_elements_text(uniq) as card;

    n := coalesce(array_length(cards, 1), 0);
    for i in 1..n loop
      for j in i+1..n loop
        for k in j+1..n loop
          for l in k+1..n loop
            for m in l+1..n loop
                pick := jsonb_build_array(cards[i], cards[j], cards[k], cards[l], cards[m]);
                candidate := public.poker_rank_five(pick);
                if candidate is null then
                    continue;
                end if;
                if best is null
                   or (candidate->>'category')::int > (best->>'category')::int
                   or (
                        (candidate->>'category')::int = (best->>'category')::int
                        and candidate->'tiebreakers' > best->'tiebreakers'
                   )
                then
                    best := candidate;
                end if;
            end loop;
          end loop;
        end loop;
      end loop;
    end loop;
    return best;
end;
$$;

create or replace function public.poker_compare_ranks(p_left jsonb, p_right jsonb)
returns integer
language sql
immutable
as $$
    select case
        when p_left is null and p_right is null then 0
        when p_left is null then -1
        when p_right is null then 1
        when (p_left->>'category')::int > (p_right->>'category')::int then 1
        when (p_left->>'category')::int < (p_right->>'category')::int then -1
        when p_left->'tiebreakers' > p_right->'tiebreakers' then 1
        when p_left->'tiebreakers' < p_right->'tiebreakers' then -1
        else 0
    end;
$$;

-- ---------------------------------------------------------------------------
-- Seat / street helpers
-- ---------------------------------------------------------------------------

create or replace function public.poker_action_order(p_seats integer[], p_dealer integer)
returns integer[]
language plpgsql
immutable
as $$
declare
    sorted integer[];
    pivot int;
begin
    select array_agg(s order by s) into sorted from unnest(p_seats) as s;
    if sorted is null then
        return '{}';
    end if;
    select min(i) into pivot
    from generate_subscripts(sorted, 1) as i
    where sorted[i] > p_dealer;
    if pivot is null then
        return sorted;
    end if;
    return sorted[pivot:] || sorted[:pivot-1];
end;
$$;

create or replace function public.poker_remaining(p_stack bigint, p_committed bigint)
returns bigint
language sql
immutable
as $$
    select greatest(0, coalesce(p_stack, 0) - coalesce(p_committed, 0));
$$;

create or replace function public.poker_street_board_count(p_street text)
returns integer
language sql
immutable
as $$
    select case p_street
        when 'preflop' then 0
        when 'flop' then 3
        when 'turn' then 4
        when 'river' then 5
        when 'showdown' then 5
        else 0
    end;
$$;

create or replace function public.poker_next_street(p_street text)
returns text
language sql
immutable
as $$
    select case p_street
        when 'preflop' then 'flop'
        when 'flop' then 'turn'
        when 'turn' then 'river'
        when 'river' then 'showdown'
        else null
    end;
$$;

create or replace function public.poker_draw_card(p_hand_id uuid)
returns text
language plpgsql
volatile
as $$
declare
    deck jsonb;
    card text;
begin
    select h.deck into deck from public.poker_hands h where h.id = p_hand_id;
    if deck is null or jsonb_array_length(deck) = 0 then
        return null;
    end if;
    card := deck->>0;
    update public.poker_hands
    set deck = coalesce(deck - 0, '[]'::jsonb)
    where id = p_hand_id;
    return card;
end;
$$;

create or replace function public.poker_call_target(p_hand_id uuid)
returns bigint
language plpgsql
stable
as $$
declare
    hand public.poker_hands;
    highest bigint;
begin
    select * into hand from public.poker_hands where id = p_hand_id;
    select coalesce(max(street_committed_cents), 0) into highest
    from public.poker_hand_seats where hand_id = p_hand_id;
    if hand.street = 'preflop' then
        return greatest(highest, hand.ante_cents);
    end if;
    return highest;
end;
$$;

create or replace function public.poker_needs_action(
    p_folded boolean,
    p_remaining bigint,
    p_has_acted boolean,
    p_street_committed bigint,
    p_call_target bigint
)
returns boolean
language sql
immutable
as $$
    select not p_folded
       and p_remaining > 0
       and (not p_has_acted or p_street_committed < p_call_target);
$$;

create or replace function public.poker_next_acting_seat(p_hand_id uuid, p_after integer)
returns integer
language plpgsql
stable
as $$
declare
    hand public.poker_hands;
    order_seats integer[];
    start_at int := 1;
    i int;
    seat_no int;
    rec record;
    call_target bigint;
    contenders int;
begin
    select * into hand from public.poker_hands where id = p_hand_id;
    select count(*) into contenders
    from public.poker_hand_seats
    where hand_id = p_hand_id and not is_folded;
    if contenders < 2 then
        return null;
    end if;

    select public.poker_action_order(array_agg(seat_number), hand.dealer_seat)
    into order_seats
    from public.poker_hand_seats
    where hand_id = p_hand_id;

    if order_seats is null or array_length(order_seats, 1) is null then
        return null;
    end if;

    call_target := public.poker_call_target(p_hand_id);
    if p_after is not null then
        select min(i) into start_at
        from generate_subscripts(order_seats, 1) as i
        where order_seats[i] = p_after;
        if start_at is null then
            start_at := 1;
        else
            start_at := start_at + 1;
        end if;
    end if;

    for i in 0 .. coalesce(array_length(order_seats, 1), 0) - 1 loop
        seat_no := order_seats[1 + ((start_at - 1 + i) % array_length(order_seats, 1))];
        select * into rec
        from public.poker_hand_seats
        where hand_id = p_hand_id and seat_number = seat_no;
        if public.poker_needs_action(
            rec.is_folded,
            public.poker_remaining(rec.stack_cents, rec.committed_cents),
            rec.has_acted,
            rec.street_committed_cents,
            call_target
        ) then
            return seat_no;
        end if;
    end loop;
    return null;
end;
$$;

create or replace function public.poker_first_to_act(p_hand_id uuid)
returns integer
language plpgsql
stable
as $$
declare
    able int;
begin
    select count(*) into able
    from public.poker_hand_seats
    where hand_id = p_hand_id
      and not is_folded
      and public.poker_remaining(stack_cents, committed_cents) > 0;
    if able < 2 then
        return null;
    end if;
    return public.poker_next_acting_seat(p_hand_id, null);
end;
$$;

-- ---------------------------------------------------------------------------
-- Snapshot the public hand (no deck; hole cards only when revealed).
-- ---------------------------------------------------------------------------

create or replace function public.poker_public_seat(p_seat public.poker_hand_seats, p_revealed boolean)
returns jsonb
language sql
stable
as $$
    select jsonb_build_object(
        'id', p_seat.id,
        'seatNumber', p_seat.seat_number,
        'playerKey', p_seat.player_key,
        'playerName', p_seat.player_name,
        'stack', public.poker_cents_text(p_seat.stack_cents),
        'committed', public.poker_cents_text(p_seat.committed_cents),
        'streetCommitted', public.poker_cents_text(p_seat.street_committed_cents),
        'hasActed', p_seat.has_acted,
        'isFolded', p_seat.is_folded,
        'cards', case
            when p_revealed and not p_seat.is_folded then p_seat.hole_cards
            else '[]'::jsonb
        end,
        'awarded', public.poker_cents_text(p_seat.awarded_cents),
        'toppedUp', public.poker_cents_text(p_seat.topped_up_cents),
        'handSummary', p_seat.hand_summary
    );
$$;

create or replace function public.poker_hand_snapshot(p_hand_id uuid, p_viewer_key text default null)
returns jsonb
language plpgsql
stable
as $$
declare
    hand public.poker_hands;
    seats jsonb := '[]'::jsonb;
    rec public.poker_hand_seats;
    seat_json jsonb;
begin
    select * into hand from public.poker_hands where id = p_hand_id;
    if not found then
        return null;
    end if;

    for rec in
        select * from public.poker_hand_seats
        where hand_id = p_hand_id
        order by seat_number
    loop
        seat_json := public.poker_public_seat(rec, hand.is_revealed);
        if p_viewer_key is not null and rec.player_key = p_viewer_key then
            seat_json := jsonb_set(seat_json, '{cards}', rec.hole_cards);
        end if;
        seats := seats || jsonb_build_array(seat_json);
    end loop;

    return jsonb_build_object(
        'id', hand.id,
        'version', 3,
        'handNumber', hand.hand_number,
        'revision', hand.revision,
        'dealerSeat', hand.dealer_seat,
        'ante', public.poker_cents_text(hand.ante_cents),
        'street', hand.street,
        'board', hand.board,
        'deck', '[]'::jsonb,
        'actingSeat', hand.acting_seat,
        'isComplete', hand.is_complete,
        'isRevealed', hand.is_revealed,
        'winnerSeats', to_jsonb(hand.winner_seats),
        'resultSummary', hand.result_summary,
        'seats', seats
    );
end;
$$;

create or replace function public.poker_publish_snapshot(p_hand_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    code text;
    snapshot jsonb;
begin
    select invite_code into code from public.poker_hands where id = p_hand_id;
    snapshot := public.poker_hand_snapshot(p_hand_id, null);
    perform set_config('poker.engine', 'on', true);
    update public.open_tables
    set hand = snapshot,
        is_started = true,
        updated_at = now()
    where invite_code = code;
end;
$$;

-- ---------------------------------------------------------------------------
-- Settlement — the only path that moves chips for a hand.
-- ---------------------------------------------------------------------------

create or replace function public.poker_side_pots(p_hand_id uuid)
returns table(amount_cents bigint, eligible_seats integer[])
language plpgsql
stable
as $$
declare
    levels bigint[];
    previous bigint := 0;
    level bigint;
    pot_amount bigint;
    leftover bigint;
    eligible integer[];
    all_eligible integer[];
    pots jsonb := '[]'::jsonb;
    pot jsonb;
begin
    select array_agg(seat_number) into all_eligible
    from public.poker_hand_seats
    where hand_id = p_hand_id and not is_folded;

    select array_agg(distinct committed_cents order by committed_cents) into levels
    from public.poker_hand_seats
    where hand_id = p_hand_id
      and not is_folded
      and committed_cents > 0;

    if levels is null then
        levels := '{}';
    end if;

    foreach level in array levels loop
        select coalesce(sum(greatest(
            least(committed_cents, level) - previous, 0
        )), 0)
        into pot_amount
        from public.poker_hand_seats
        where hand_id = p_hand_id;

        select array_agg(seat_number) into eligible
        from public.poker_hand_seats
        where hand_id = p_hand_id
          and not is_folded
          and committed_cents >= level;

        if pot_amount > 0 then
            pots := pots || jsonb_build_array(jsonb_build_object(
                'amount', pot_amount,
                'eligible', to_jsonb(coalesce(eligible, '{}'::integer[]))
            ));
        end if;
        previous := level;
    end loop;

    -- Chips nobody was asked to match stay in the last pot. They do not
    -- become a new pot the remaining field can share.
    select coalesce(sum(greatest(committed_cents - previous, 0)), 0)
    into leftover
    from public.poker_hand_seats
    where hand_id = p_hand_id;

    if leftover > 0 then
        if jsonb_array_length(pots) = 0 then
            pots := jsonb_build_array(jsonb_build_object(
                'amount', leftover,
                'eligible', to_jsonb(coalesce(all_eligible, '{}'))
            ));
        else
            pots := jsonb_set(
                pots,
                array[(jsonb_array_length(pots) - 1)::text, 'amount'],
                to_jsonb(((pots -> (jsonb_array_length(pots) - 1) ->> 'amount')::bigint + leftover))
            );
        end if;
    end if;

    for pot in select value from jsonb_array_elements(pots) loop
        amount_cents := (pot->>'amount')::bigint;
        eligible_seats := array(select jsonb_array_elements_text(pot->'eligible')::int);
        return next;
    end loop;
end;
$$;

create or replace function public.poker_ordered_from_dealer(p_hand_id uuid, p_seats integer[])
returns integer[]
language plpgsql
stable
as $$
declare
    dealer int;
    all_seats integer[];
    order_seats integer[];
begin
    select dealer_seat into dealer from public.poker_hands where id = p_hand_id;
    select array_agg(seat_number) into all_seats
    from public.poker_hand_seats where hand_id = p_hand_id;
    order_seats := public.poker_action_order(all_seats, dealer);
    return array(
        select s
        from unnest(p_seats) as s
        order by coalesce(array_position(order_seats, s), s)
    );
end;
$$;

create or replace function public.poker_best_seats(
    p_hand_id uuid,
    p_eligible integer[],
    p_ranks jsonb
)
returns integer[]
language plpgsql
stable
as $$
declare
    live integer[];
    best jsonb;
    winners integer[] := '{}';
    seat_no int;
    rank jsonb;
begin
    select array_agg(s.seat_number) into live
    from public.poker_hand_seats s
    where s.hand_id = p_hand_id
      and s.seat_number = any(p_eligible)
      and not s.is_folded;

    if live is null or array_length(live, 1) is null then
        return '{}';
    end if;
    if array_length(live, 1) = 1 then
        return live;
    end if;

    foreach seat_no in array live loop
        rank := p_ranks -> seat_no::text;
        if rank is null then
            continue;
        end if;
        if best is null or public.poker_compare_ranks(rank, best) > 0 then
            best := rank;
            winners := array[seat_no];
        elsif public.poker_compare_ranks(rank, best) = 0 then
            winners := winners || seat_no;
        end if;
    end loop;

    if winners is null or array_length(winners, 1) is null then
        return live;
    end if;
    return public.poker_ordered_from_dealer(p_hand_id, winners);
end;
$$;

create or replace function public.poker_split_cents(p_amount bigint, p_ways integer)
returns bigint[]
language plpgsql
immutable
as $$
declare
    base bigint;
    shares bigint[];
    i int;
begin
    if p_ways <= 1 then
        return array[greatest(p_amount, 0)];
    end if;
    base := greatest(p_amount, 0) / p_ways;
    shares := array_fill(base, array[p_ways]);
    shares[1] := shares[1] + (greatest(p_amount, 0) % p_ways);
    return shares;
end;
$$;

create or replace function public.poker_pay_pots(p_hand_id uuid, p_ranks jsonb)
returns void
language plpgsql
volatile
as $$
declare
    pot record;
    winners integer[];
    shares bigint[];
    i int;
    awarded jsonb := '{}'::jsonb;
    winner_list integer[] := '{}';
    amount bigint;
    leftover_attached boolean := false;
    pots jsonb := '[]'::jsonb;
    pot_json jsonb;
    last_idx int;
begin
    -- Build pots, attaching unmatched leftover chips to the last pot so they
    -- cannot vanish and cannot be reclaimed by a leaver.
    for pot in select * from public.poker_side_pots(p_hand_id) loop
        pots := pots || jsonb_build_array(
            jsonb_build_object(
                'amount', pot.amount_cents,
                'eligible', to_jsonb(pot.eligible_seats)
            )
        );
    end loop;

    -- poker_side_pots may emit leftover as its own row with the live field.
    -- That is already a pot; pay it as-is.

    for pot_json in select value from jsonb_array_elements(pots) loop
        winners := public.poker_best_seats(
            p_hand_id,
            array(select jsonb_array_elements_text(pot_json->'eligible')::int),
            p_ranks
        );
        if winners is null or array_length(winners, 1) is null then
            continue;
        end if;
        shares := public.poker_split_cents((pot_json->>'amount')::bigint, array_length(winners, 1));
        for i in 1 .. array_length(winners, 1) loop
            awarded := jsonb_set(
                awarded,
                array[winners[i]::text],
                to_jsonb(coalesce((awarded->>winners[i]::text)::bigint, 0) + shares[i])
            );
            if not winners[i] = any(winner_list) then
                winner_list := winner_list || winners[i];
            end if;
        end loop;
    end loop;

    update public.poker_hand_seats s
    set awarded_cents = coalesce((awarded->>s.seat_number::text)::bigint, 0)
    where s.hand_id = p_hand_id;

    update public.poker_hands
    set winner_seats = (
        select coalesce(array_agg(s order by s), '{}')
        from unnest(winner_list) as s
    )
    where id = p_hand_id;
end;
$$;

create or replace function public.poker_apply_vault_settlement(p_hand_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    hand public.poker_hands;
    tbl public.vault_tables;
    rec public.poker_hand_seats;
    moves jsonb := '[]'::jsonb;
    total bigint := 0;
    delta bigint;
    account uuid;
    posted public.vault_ledger_transactions;
    host_uid uuid;
begin
    select * into hand from public.poker_hands where id = p_hand_id for update;
    if not found or hand.is_settled then
        return;
    end if;

    select * into tbl from public.vault_tables where invite_code = hand.invite_code;
    if not found then
        update public.poker_hands set is_settled = true where id = p_hand_id;
        return;
    end if;

    for rec in select * from public.poker_hand_seats where hand_id = p_hand_id loop
        delta := rec.awarded_cents - rec.committed_cents;
        if delta = 0 then
            continue;
        end if;
        account := public.vault_account(rec.user_id, 'in_play', tbl.currency_code, hand.invite_code);
        moves := moves || jsonb_build_array(
            jsonb_build_object('account_id', account, 'amount_cents', delta)
        );
        total := total + delta;
    end loop;

    if total <> 0 then
        raise exception 'poker: settlement is not zero-sum (off by % cents)', total
            using errcode = '23514';
    end if;

    update public.poker_hands set is_settled = true where id = p_hand_id;

    if jsonb_array_length(moves) = 0 then
        return;
    end if;

    host_uid := tbl.host_user_id;
    posted := public.vault_post_transaction(
        host_uid, 'table_hand', moves,
        'hand:' || hand.invite_code || ':' || hand.id::text,
        hand.invite_code,
        jsonb_build_object('hand_id', hand.id)
    );

    if exists (
        select 1 from public.vault_statement_entries
        where ledger_transaction_id = posted.id
    ) then
        return;
    end if;

    for rec in select * from public.poker_hand_seats where hand_id = p_hand_id loop
        delta := rec.awarded_cents - rec.committed_cents;
        if delta = 0 then
            continue;
        end if;
        account := public.vault_account(rec.user_id, 'in_play', tbl.currency_code, hand.invite_code);
        update public.vault_table_stakes
        set in_play_cents = (select balance_cents from public.vault_accounts where id = account)
        where invite_code = hand.invite_code and user_id = rec.user_id;

        perform public.vault_add_statement(
            rec.user_id,
            case when delta > 0 then 'table_winnings' else 'table_loss' end,
            'completed', 0, tbl.currency_code, posted.id, null, null, hand.invite_code,
            case when delta > 0 then 'Won at the table' else 'Lost at the table' end
        );
    end loop;

    perform public.vault_log(
        host_uid, 'table_hand', 'ok', null, posted.reference_code, hand.invite_code,
        jsonb_build_object('hand_id', hand.id, 'source', 'poker_engine')
    );
end;
$$;

create or replace function public.poker_finish_by_fold(p_hand_id uuid)
returns void
language plpgsql
volatile
as $$
declare
    live integer[];
begin
    perform public.poker_pay_pots(p_hand_id, '{}'::jsonb);

    select winner_seats into live from public.poker_hands where id = p_hand_id;
    if live is null or array_length(live, 1) is null then
        select array_agg(seat_number) into live
        from public.poker_hand_seats
        where hand_id = p_hand_id and not is_folded;
        update public.poker_hands
        set winner_seats = coalesce(live, '{}')
        where id = p_hand_id;
    end if;

    update public.poker_hands
    set is_complete = true,
        is_revealed = false,
        acting_seat = null,
        result_summary = 'Everyone else folded.',
        updated_at = now()
    where id = p_hand_id;

    perform public.poker_apply_vault_settlement(p_hand_id);
end;
$$;

create or replace function public.poker_showdown(p_hand_id uuid)
returns void
language plpgsql
volatile
as $$
declare
    rec public.poker_hand_seats;
    board jsonb;
    rank jsonb;
    ranks jsonb := '{}'::jsonb;
    top_summary text;
    top_awarded bigint := -1;
begin
    select h.board into board from public.poker_hands h where h.id = p_hand_id;

    for rec in
        select * from public.poker_hand_seats
        where hand_id = p_hand_id and not is_folded
    loop
        rank := public.poker_best_hand(rec.hole_cards || board);
        if rank is not null then
            ranks := jsonb_set(ranks, array[rec.seat_number::text], rank);
            update public.poker_hand_seats
            set hand_summary = rank->>'summary'
            where id = rec.id;
        end if;
    end loop;

    perform public.poker_pay_pots(p_hand_id, ranks);

    select s.hand_summary, s.awarded_cents
    into top_summary, top_awarded
    from public.poker_hand_seats s
    where s.hand_id = p_hand_id
    order by s.awarded_cents desc
    limit 1;

    update public.poker_hands
    set street = 'showdown',
        is_complete = true,
        is_revealed = true,
        acting_seat = null,
        result_summary = top_summary,
        updated_at = now()
    where id = p_hand_id;

    perform public.poker_apply_vault_settlement(p_hand_id);
end;
$$;

create or replace function public.poker_open_street(p_hand_id uuid, p_street text)
returns void
language plpgsql
volatile
as $$
declare
    needed int;
    have int;
    card text;
begin
    update public.poker_hands
    set street = p_street, updated_at = now()
    where id = p_hand_id;

    select jsonb_array_length(board) into have
    from public.poker_hands where id = p_hand_id;
    needed := public.poker_street_board_count(p_street);
    while have < needed loop
        card := public.poker_draw_card(p_hand_id);
        exit when card is null;
        update public.poker_hands
        set board = board || jsonb_build_array(card)
        where id = p_hand_id;
        have := have + 1;
    end loop;

    update public.poker_hand_seats
    set street_committed_cents = 0,
        has_acted = false
    where hand_id = p_hand_id;
end;
$$;

create or replace function public.poker_close_street(p_hand_id uuid)
returns void
language plpgsql
volatile
as $$
declare
    contenders int;
    street text;
    following text;
    next_actor int;
begin
    update public.poker_hands set acting_seat = null where id = p_hand_id;

    select count(*) into contenders
    from public.poker_hand_seats
    where hand_id = p_hand_id and not is_folded;
    if contenders < 2 then
        perform public.poker_finish_by_fold(p_hand_id);
        return;
    end if;

    select h.street into street from public.poker_hands h where h.id = p_hand_id;
    following := public.poker_next_street(street);
    while following is not null and following <> 'showdown' loop
        perform public.poker_open_street(p_hand_id, following);
        next_actor := public.poker_first_to_act(p_hand_id);
        if next_actor is not null then
            update public.poker_hands
            set acting_seat = next_actor, updated_at = now()
            where id = p_hand_id;
            return;
        end if;
        street := following;
        following := public.poker_next_street(street);
    end loop;

    -- Run the remaining board out if we skipped streets (everyone all-in).
    if (select jsonb_array_length(board) from public.poker_hands where id = p_hand_id) < 5 then
        perform public.poker_open_street(p_hand_id, 'river');
    end if;
    perform public.poker_showdown(p_hand_id);
end;
$$;

create or replace function public.poker_advance(p_hand_id uuid, p_after integer)
returns void
language plpgsql
volatile
as $$
declare
    nxt int;
begin
    nxt := public.poker_next_acting_seat(p_hand_id, p_after);
    update public.poker_hands
    set acting_seat = nxt, revision = revision + 1, updated_at = now()
    where id = p_hand_id;
    if nxt is null then
        perform public.poker_close_street(p_hand_id);
    end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Create a hand. The deck argument is only for the internal/test entry point.
-- ---------------------------------------------------------------------------

create or replace function public.poker_start_hand_internal(
    p_invite_code text,
    p_deck jsonb default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    uid uuid := public.vault_require_user();
    code text := upper(trim(p_invite_code));
    tbl_row public.open_tables;
    live public.poker_hands;
    player record;
    players_count int := 0;
    dealer int;
    prev_dealer int;
    hand_id uuid := gen_random_uuid();
    hand_no int;
    ante bigint;
    deck jsonb;
    order_seats integer[];
    seat_no int;
    card text;
    pass int;
    first_actor int;
begin
    if code = '' then
        raise exception 'poker: unknown table' using errcode = 'P0002';
    end if;

    select * into tbl_row from public.open_tables where invite_code = code for update;
    if not found then
        raise exception 'poker: unknown table' using errcode = 'P0002';
    end if;

    if not exists (
        select 1
        from jsonb_array_elements(coalesce(tbl_row.seats, '[]'::jsonb)) seat
        where seat->>'playerKey' = uid::text
    ) then
        raise exception 'poker: you are not at that table' using errcode = '42501';
    end if;

    select * into live
    from public.poker_hands
    where invite_code = code and not is_complete
    for update;
    if found then
        return public.poker_hand_snapshot(live.id, uid::text);
    end if;

    create temporary table if not exists poker_start_players (
        user_id uuid,
        player_key text,
        seat_number int,
        player_name text,
        stack_cents bigint,
        is_host boolean
    ) on commit drop;
    delete from poker_start_players;

    insert into poker_start_players (user_id, player_key, seat_number, player_name, stack_cents, is_host)
    select s.user_id,
           s.player_key,
           nullif(seat->>'seatNumber', '')::int,
           coalesce(nullif(seat->>'playerName', ''), s.display_name, 'Player'),
           s.in_play_cents,
           coalesce((seat->>'isHost')::boolean, tbl_row.host_user_id = s.user_id)
    from public.vault_table_stakes s
    join jsonb_array_elements(coalesce(tbl_row.seats, '[]'::jsonb)) seat
      on seat->>'playerKey' = s.player_key
    where s.invite_code = code
      and s.status = 'seated'
      and s.in_play_cents > 0
      and nullif(seat->>'seatNumber', '')::int between 1 and 8;

    select count(*) into players_count from poker_start_players;
    if players_count < 2 then
        raise exception 'poker: two players need money on the table to deal a hand'
            using errcode = 'P0002';
    end if;

    select dealer_seat into prev_dealer
    from public.poker_hands
    where invite_code = code
    order by hand_number desc
    limit 1;

    if prev_dealer is not null then
        dealer := (
            public.poker_action_order(
                array(select seat_number from poker_start_players),
                prev_dealer
            )
        )[1];
    else
        select seat_number into dealer
        from poker_start_players
        where is_host
        order by seat_number
        limit 1;
        if dealer is null then
            select min(seat_number) into dealer from poker_start_players;
        end if;
    end if;

    select coalesce(max(hand_number), 0) + 1 into hand_no
    from public.poker_hands where invite_code = code;

    ante := public.poker_ante_cents(tbl_row.ante_amount);
    if p_deck is null or jsonb_array_length(p_deck) = 0 then
        deck := public.poker_shuffle_deck(public.poker_full_deck());
    else
        deck := p_deck;
        -- Append any missing cards so a stacked test deck still has a board.
        deck := deck || coalesce((
            select jsonb_agg(card)
            from jsonb_array_elements_text(public.poker_full_deck()) as card
            where not exists (
                select 1
                from jsonb_array_elements_text(p_deck) as dealt
                where dealt = card
            )
        ), '[]'::jsonb);
    end if;

    insert into public.poker_hands (
        id, invite_code, hand_number, revision, dealer_seat, ante_cents, deck
    ) values (
        hand_id, code, hand_no, 1, dealer, ante, deck
    );

    insert into public.poker_hand_seats (
        hand_id, user_id, player_key, seat_number, player_name, stack_cents
    )
    select hand_id, user_id, player_key, seat_number, player_name, stack_cents
    from poker_start_players;

    select public.poker_action_order(array_agg(seat_number), dealer)
    into order_seats
    from public.poker_hand_seats
    where hand_id = hand_id;

    for pass in 1..2 loop
        foreach seat_no in array order_seats loop
            card := public.poker_draw_card(hand_id);
            update public.poker_hand_seats
            set hole_cards = hole_cards || jsonb_build_array(card)
            where hand_id = hand_id and seat_number = seat_no;
        end loop;
    end loop;

    first_actor := public.poker_first_to_act(hand_id);
    update public.poker_hands
    set acting_seat = first_actor, updated_at = now()
    where id = hand_id;
    if first_actor is null then
        perform public.poker_close_street(hand_id);
    end if;

    perform public.poker_publish_snapshot(hand_id);
    return public.poker_hand_snapshot(hand_id, uid::text);
end;
$$;

create or replace function public.poker_start_hand(p_invite_code text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
    -- Clients cannot pass a deck. The server shuffles.
    return public.poker_start_hand_internal(p_invite_code, null);
end;
$$;

-- ---------------------------------------------------------------------------
-- Betting
-- ---------------------------------------------------------------------------

create or replace function public.poker_apply_action(
    p_hand_id uuid,
    p_player_key text,
    p_action text,
    p_amount_cents bigint
)
returns void
language plpgsql
volatile
as $$
declare
    hand public.poker_hands;
    seat public.poker_hand_seats;
    action text := lower(trim(p_action));
    call_target bigint;
    to_call bigint;
    remaining bigint;
    street_cap bigint;
    target bigint;
    added bigint;
    is_all_in boolean;
begin
    select * into hand from public.poker_hands where id = p_hand_id for update;
    if hand.is_complete or hand.acting_seat is null then
        raise exception 'poker: the betting on this street is already done'
            using errcode = '42501';
    end if;

    select * into seat
    from public.poker_hand_seats
    where hand_id = p_hand_id and player_key = p_player_key
    for update;
    if not found or seat.seat_number <> hand.acting_seat then
        raise exception 'poker: it is not your turn yet' using errcode = '42501';
    end if;
    if seat.is_folded then
        raise exception 'poker: it is not your turn yet' using errcode = '42501';
    end if;

    if action not in ('check', 'call', 'bet', 'raise', 'fold', 'all-in', 'allin', 'all_in') then
        raise exception 'poker: unknown action' using errcode = '22023';
    end if;
    if action in ('allin', 'all_in') then
        action := 'all-in';
    end if;

    call_target := public.poker_call_target(p_hand_id);
    remaining := public.poker_remaining(seat.stack_cents, seat.committed_cents);
    street_cap := seat.street_committed_cents + remaining;
    to_call := least(greatest(call_target - seat.street_committed_cents, 0), remaining);

    if action = 'fold' then
        update public.poker_hand_seats
        set is_folded = true, has_acted = true
        where id = seat.id;
    elsif action = 'check' then
        if to_call > 0 then
            raise exception 'poker: that move is not available right now'
                using errcode = '42501';
        end if;
        update public.poker_hand_seats set has_acted = true where id = seat.id;
    elsif action = 'call' then
        update public.poker_hand_seats
        set committed_cents = committed_cents + to_call,
            street_committed_cents = street_committed_cents + to_call,
            has_acted = true
        where id = seat.id;
    elsif action = 'all-in' then
        if remaining <= 0 then
            raise exception 'poker: that move is not available right now'
                using errcode = '42501';
        end if;
        update public.poker_hand_seats
        set committed_cents = committed_cents + remaining,
            street_committed_cents = street_committed_cents + remaining,
            has_acted = true
        where id = seat.id;
        if seat.street_committed_cents + remaining > call_target then
            update public.poker_hand_seats
            set has_acted = false
            where hand_id = p_hand_id and id <> seat.id and not is_folded;
        end if;
    else
        -- bet / raise
        if p_amount_cents is null then
            raise exception 'poker: a bet needs an amount' using errcode = '22023';
        end if;
        if p_amount_cents <= 0 then
            raise exception 'poker: a bet has to be more than the table has already put in'
                using errcode = '23514';
        end if;
        if p_amount_cents > street_cap then
            raise exception 'poker: you do not have that many chips'
                using errcode = '23514';
        end if;
        target := p_amount_cents;
        is_all_in := target = street_cap;
        if target <= seat.street_committed_cents or (target <= call_target and not is_all_in) then
            raise exception 'poker: a bet has to be more than the table has already put in'
                using errcode = '23514';
        end if;
        added := target - seat.street_committed_cents;
        update public.poker_hand_seats
        set committed_cents = committed_cents + added,
            street_committed_cents = street_committed_cents + added,
            has_acted = true
        where id = seat.id;
        if target > call_target then
            update public.poker_hand_seats
            set has_acted = false
            where hand_id = p_hand_id and id <> seat.id and not is_folded;
        end if;
    end if;

    perform public.poker_advance(p_hand_id, seat.seat_number);
end;
$$;

create or replace function public.poker_act(
    p_invite_code text,
    p_action text,
    p_amount_cents bigint default null,
    p_action_id text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    uid uuid := public.vault_require_user();
    code text := upper(trim(p_invite_code));
    hand public.poker_hands;
    action_key text := nullif(trim(coalesce(p_action_id, '')), '');
    existing public.poker_hand_actions;
begin
    if action_key is null then
        raise exception 'poker: every action needs an action id' using errcode = '22023';
    end if;

    select * into hand
    from public.poker_hands
    where invite_code = code and not is_complete
    for update;
    if not found then
        raise exception 'poker: there is no hand in progress' using errcode = 'P0002';
    end if;

    select * into existing
    from public.poker_hand_actions
    where hand_id = hand.id and action_id = action_key;
    if found then
        -- The same action id is a retry, not a second bet.
        return public.poker_hand_snapshot(hand.id, uid::text);
    end if;

    perform public.poker_apply_action(hand.id, uid::text, p_action, p_amount_cents);

    insert into public.poker_hand_actions (
        hand_id, action_id, player_key, action, amount_cents, revision
    )
    select hand.id, action_key, uid::text, lower(trim(p_action)), p_amount_cents, h.revision
    from public.poker_hands h where h.id = hand.id;

    perform public.poker_publish_snapshot(hand.id);
    return public.poker_hand_snapshot(hand.id, uid::text);
end;
$$;

create or replace function public.poker_hand_view(p_invite_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    uid uuid := public.vault_require_user();
    code text := upper(trim(p_invite_code));
    hand_id uuid;
    seated boolean;
begin
    select exists (
        select 1
        from public.open_tables t,
             jsonb_array_elements(coalesce(t.seats, '[]'::jsonb)) seat
        where t.invite_code = code
          and seat->>'playerKey' = uid::text
    ) into seated;

    if not seated then
        raise exception 'poker: you are not at that table' using errcode = '42501';
    end if;

    select id into hand_id
    from public.poker_hands
    where invite_code = code
    order by hand_number desc
    limit 1;

    if hand_id is null then
        return null;
    end if;
    return public.poker_hand_snapshot(hand_id, uid::text);
end;
$$;

-- Fold a player who is cashing off. Not their turn. Committed chips stay.
create or replace function public.poker_withdraw_player(p_invite_code text, p_player_key text)
returns bigint
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    code text := upper(trim(p_invite_code));
    hand public.poker_hands;
    seat public.poker_hand_seats;
    contenders int;
begin
    select * into hand
    from public.poker_hands
    where invite_code = code and not is_complete
    for update;
    if not found then
        return 0;
    end if;

    select * into seat
    from public.poker_hand_seats
    where hand_id = hand.id and player_key = p_player_key
    for update;
    if not found or seat.is_folded then
        return 0;
    end if;

    update public.poker_hand_seats
    set is_folded = true, has_acted = true
    where id = seat.id;

    update public.poker_hands
    set revision = revision + 1, updated_at = now()
    where id = hand.id;

    select count(*) into contenders
    from public.poker_hand_seats
    where hand_id = hand.id and not is_folded;

    if contenders < 2 then
        update public.poker_hands set acting_seat = null where id = hand.id;
        perform public.poker_close_street(hand.id);
    elsif hand.acting_seat = seat.seat_number then
        perform public.poker_advance(hand.id, seat.seat_number);
    end if;

    perform public.poker_publish_snapshot(hand.id);

    if (select is_complete from public.poker_hands where id = hand.id) then
        return 0;
    end if;
    return (select committed_cents from public.poker_hand_seats where id = seat.id);
end;
$$;

create or replace function public.poker_live_committed_cents(p_invite_code text, p_player_key text)
returns bigint
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    committed bigint;
begin
    select s.committed_cents into committed
    from public.poker_hand_seats s
    join public.poker_hands h on h.id = s.hand_id
    where h.invite_code = upper(trim(p_invite_code))
      and not h.is_complete
      and s.player_key = p_player_key;
    return coalesce(committed, 0);
end;
$$;

-- ---------------------------------------------------------------------------
-- vault_record_hand: clients can no longer name a winner.
-- ---------------------------------------------------------------------------

create or replace function public.vault_record_hand(
    p_invite_code text,
    p_hand_id text,
    p_deltas jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
    perform public.vault_require_user();
    perform public.vault_log(
        public.vault_require_user(), 'table_hand', 'refused_client_result',
        null, null, upper(trim(p_invite_code)),
        jsonb_build_object('hand_id', p_hand_id)
    );
    raise exception 'vault: the server records the hand. send a betting action, not a result'
        using errcode = '42501';
end;
$$;

-- ---------------------------------------------------------------------------
-- Leaving: fold, keep committed chips in the pot, return only what is free.
-- ---------------------------------------------------------------------------

create or replace function public.vault_leave_table(
    p_invite_code text,
    p_idempotency_key text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
    uid uuid := public.vault_require_user();
    code text := upper(trim(p_invite_code));
    tbl public.vault_tables;
    stake public.vault_table_stakes;
    in_play uuid;
    available uuid;
    final_cents bigint;
    withheld bigint := 0;
    return_cents bigint;
    bought_in bigint;
    posted public.vault_ledger_transactions;
begin
    select * into tbl from public.vault_tables where invite_code = code;
    if not found then
        raise exception 'vault: unknown table' using errcode = 'P0002';
    end if;

    select * into stake
    from public.vault_table_stakes
    where invite_code = code and user_id = uid
    for update;

    if not found then
        raise exception 'vault: you are not at that table' using errcode = 'P0002';
    end if;

    if stake.status = 'left' then
        return jsonb_build_object(
            'invite_code', code,
            'bought_in_cents', stake.total_bought_in_cents,
            'returned_cents', stake.returned_cents,
            'net_cents', stake.returned_cents - stake.total_bought_in_cents,
            'reference_code', '',
            'already_settled', true
        );
    end if;

    -- Fold first. If that ends the hand the pot is paid immediately and
    -- nothing is withheld. If the hand goes on, committed chips stay in play
    -- until the server settles it — they cannot walk out of the pot.
    withheld := public.poker_withdraw_player(code, stake.player_key);
    withheld := public.poker_live_committed_cents(code, stake.player_key);

    in_play := public.vault_account(uid, 'in_play', tbl.currency_code, code);
    available := public.vault_account(uid, 'available', tbl.currency_code);

    select balance_cents into final_cents
    from public.vault_accounts where id = in_play for update;

    if withheld > final_cents then
        withheld := final_cents;
    end if;
    return_cents := final_cents - withheld;
    bought_in := stake.total_bought_in_cents;

    if return_cents > 0 then
        posted := public.vault_post_transaction(
            uid, 'table_return',
            jsonb_build_array(
                jsonb_build_object('account_id', in_play, 'amount_cents', -return_cents),
                jsonb_build_object('account_id', available, 'amount_cents', return_cents)
            ),
            p_idempotency_key, code,
            jsonb_build_object('bought_in_cents', bought_in, 'withheld_cents', withheld)
        );

        perform public.vault_add_statement(
            uid, 'table_return', 'completed', 0, tbl.currency_code,
            posted.id, null, null, code, 'Returned from the table to your Vault'
        );
    end if;

    update public.vault_table_stakes
    set status = 'left',
        left_at = now(),
        in_play_cents = withheld,
        returned_cents = returned_cents + return_cents
    where invite_code = code and user_id = uid;

    perform public.vault_log(uid, 'table_leave', 'ok', return_cents,
                             coalesce(posted.reference_code, 'none'), code,
                             jsonb_build_object('withheld_cents', withheld));

    return jsonb_build_object(
        'invite_code', code,
        'bought_in_cents', bought_in,
        'returned_cents', return_cents,
        'net_cents', return_cents - bought_in,
        'reference_code', coalesce(posted.reference_code, ''),
        'already_settled', false
    );
end;
$$;

-- Live-hand helper now reads the server table, not a phone-written JSON blob.
create or replace function public.open_table_live_hand_seat(
    p_invite_code text,
    p_player_key text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    return exists (
        select 1
        from public.poker_hands h
        join public.poker_hand_seats s on s.hand_id = h.id
        where h.invite_code = upper(trim(p_invite_code))
          and not h.is_complete
          and s.player_key = p_player_key
          and not s.is_folded
    );
end;
$$;

-- ---------------------------------------------------------------------------
-- open_tables.hand is server-owned. Clients cannot write it.
-- ---------------------------------------------------------------------------

create or replace function public.open_tables_guard_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    caller text := public.open_table_seat_key();
    is_host boolean;
begin
    if current_setting('poker.engine', true) = 'on' then
        return new;
    end if;

    -- No auth.uid() means service_role or a migration, not a player.
    if caller = '' then
        return new;
    end if;

    if new.id <> old.id
       or new.invite_code <> old.invite_code
       or new.host_user_id <> old.host_user_id
       or new.created_at <> old.created_at then
        raise exception 'open_tables: that table''s identity cannot be changed'
            using errcode = '42501';
    end if;

    -- The hand is the server's. A write that only touches the hand is an
    -- attack and is refused. A mixed update (seats, ante, …) keeps the
    -- server hand even if the payload carried a stale or forged copy.
    if new.hand is distinct from old.hand then
        if new.seats is not distinct from old.seats
           and new.ante_amount is not distinct from old.ante_amount
           and new.is_started is not distinct from old.is_started
           and new.session_currency_code is not distinct from old.session_currency_code
           and coalesce(new.host_display_name, '') is not distinct from coalesce(old.host_display_name, '')
           and coalesce(new.host_player_key, '') is not distinct from coalesce(old.host_player_key, '') then
            raise exception 'open_tables: the server owns the hand'
                using errcode = '42501';
        end if;
        new.hand := old.hand;
    end if;

    is_host := old.host_user_id::text = caller;
    if is_host then
        return new;
    end if;

    if new.session_currency_code is distinct from old.session_currency_code
       or new.ante_amount is distinct from old.ante_amount
       or new.is_started is distinct from old.is_started
       or coalesce(new.host_display_name, '') is distinct from coalesce(old.host_display_name, '')
       or coalesce(new.host_player_key, '') is distinct from coalesce(old.host_player_key, '') then
        raise exception 'open_tables: only the host can change this table''s settings'
            using errcode = '42501';
    end if;

    if public.open_table_other_seats(new.seats, caller)
       <> public.open_table_other_seats(old.seats, caller) then
        raise exception 'open_tables: you can only change your own seat'
            using errcode = '42501';
    end if;

    return new;
end;
$$;

drop trigger if exists open_tables_guard_update on public.open_tables;
create trigger open_tables_guard_update
    before update on public.open_tables
    for each row execute function public.open_tables_guard_update();

-- ---------------------------------------------------------------------------
-- Grants. Authenticated players may ask to start, act, or look — nothing else.
-- ---------------------------------------------------------------------------

revoke all on function public.poker_start_hand_internal(text, jsonb) from public, anon, authenticated;
revoke all on function public.poker_apply_vault_settlement(uuid) from public, anon, authenticated;
revoke all on function public.poker_apply_action(uuid, text, text, bigint) from public, anon, authenticated;
revoke all on function public.poker_withdraw_player(text, text) from public, anon, authenticated;
revoke all on function public.poker_draw_card(uuid) from public, anon, authenticated;
revoke all on function public.poker_shuffle_deck(jsonb) from public, anon;
revoke all on function public.poker_full_deck() from public, anon, authenticated;
revoke all on function public.poker_rank_five(jsonb) from public, anon, authenticated;
revoke all on function public.poker_best_hand(jsonb) from public, anon, authenticated;

revoke all on function public.poker_start_hand(text) from public, anon;
grant execute on function public.poker_start_hand(text) to authenticated;

revoke all on function public.poker_act(text, text, bigint, text) from public, anon;
grant execute on function public.poker_act(text, text, bigint, text) to authenticated;

revoke all on function public.poker_hand_view(text) from public, anon;
grant execute on function public.poker_hand_view(text) to authenticated;

revoke all on function public.vault_record_hand(text, text, jsonb) from public, anon;
grant execute on function public.vault_record_hand(text, text, jsonb) to authenticated;

revoke all on function public.vault_leave_table(text, text) from public, anon;
grant execute on function public.vault_leave_table(text, text) to authenticated;

notify pgrst, 'reload schema';
