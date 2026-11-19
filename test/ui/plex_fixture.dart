import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/sources/accounts.dart';
import 'package:lafleurmusic/sources/plex_link.dart';
import 'package:lafleurmusic/sources/source.dart';
import 'package:lafleurmusic/ui/phone/accounts_screen.dart';

import '../sources/fake_plex.dart';
import 'accounts_fixture.dart';

const plexSeed = <SeedAccount>[
  (
    type: AccountType.plex,
    name: 'Plex maison',
    base: 'https://$homeLocal:32400',
    headers: {},
  ),
];

/// The phone on the accounts screen, plex.tv and the servers faked by [tv].
Future<AccountsFixture> pumpWithPlex(
  WidgetTester tester,
  FakePlexTv tv, {
  Widget Function()? home,
  List<SeedAccount> seed = const [],
  Map<String, TestResult> Function(List<Account>)? results,
}) => pumpAccounts(
  tester,
  seed: seed,
  results: results,
  home: home ?? () => const AccountsScreen(),
  plexLink: (id) => PlexLink(
    clientId: id,
    client: tv.client(),
    deviceName: 'iPhone',
    platform: 'iOS',
    now: tester.binding.clock.now,
  ),
);
