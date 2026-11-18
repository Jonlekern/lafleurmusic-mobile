import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../sources/account_service.dart';
import '../../sources/accounts.dart';
import '../../sources/source.dart';
import '../../theme/colors.dart';
import '../../theme/widgets.dart';
import 'phone_shell.dart';

/// Fond des champs et des segments de la maquette 2.
const _fieldBg = Color(0xFF161616);
const _red = Color(0xFFFF6B6B);
const _green = Color(0xFF5FD16F);

/// Ajouter un compte (maquette 2, écran 7) ; avec [editing], le modifier ou le supprimer.
/// [first] : premier lancement, sans retour ; l'Accueil prend la place une fois le compte enregistré.
class AccountFormScreen extends StatefulWidget {
  const AccountFormScreen({
    super.key,
    this.editing,
    this.first = false,
    this.initial,
  });
  final Account? editing;
  final bool first;

  /// Formulaire déjà rempli (nouveau compte) : images de référence, mode démo.
  final AccountDraft? initial;

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _HeaderPair {
  _HeaderPair([String name = '', String value = ''])
    : name = TextEditingController(text: name),
      value = TextEditingController(text: value);
  final TextEditingController name, value;
  void dispose() {
    name.dispose();
    value.dispose();
  }
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  late final _name = TextEditingController(
    text: widget.editing?.name ?? widget.initial?.name,
  );
  late final _address = TextEditingController(
    text: widget.editing?.base.toString() ?? widget.initial?.address,
  );
  late final _user = TextEditingController(
    text: widget.editing?.user ?? widget.initial?.user,
  );
  late final _password = TextEditingController(text: widget.initial?.password);
  late final _headers = <_HeaderPair>[
    for (final e in (widget.initial?.headers ?? const {}).entries)
      _HeaderPair(e.key, e.value),
  ];
  AccountType _type = AccountType.subsonic;
  bool _busy = false;
  // dernier message sous les boutons : résultat de « Tester » ou erreur
  String? _message;
  bool _ok = false;

  bool _loaded = false;
  // modification : en-têtes du coffre pas encore lus (Tester / Enregistrer attendent)
  late bool _headersPending = widget.editing != null;
  // lecture ratée : Enregistrer garde ceux du coffre au lieu de les effacer
  bool _headersUnread = false;

  bool get _locked => _busy || _headersPending;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final a = widget.editing;
    if (a != null && !_loaded) {
      _loaded = true;
      _type = a.type;
      _loadHeaders(a.id);
    }
  }

  Future<void> _loadHeaders(String id) async {
    final accounts = AppScope.of(context).accounts;
    Map<String, String>? h;
    try {
      h = await accounts?.headers(id);
    } catch (_) {
      h = null;
    }
    if (!mounted) return;
    setState(() {
      _headersPending = false;
      _headersUnread = h == null;
      for (final e in (h ?? const <String, String>{}).entries) {
        _headers.add(_HeaderPair(e.key, e.value));
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _user, _password]) {
      c.dispose();
    }
    for (final h in _headers) {
      h.dispose();
    }
    super.dispose();
  }

  AccountDraft get _draft => AccountDraft(
    type: _type,
    name: _name.text,
    address: _address.text,
    user: _user.text,
    password: _password.text,
    headers: {
      for (final h in _headers)
        if (h.name.text.trim().isNotEmpty) h.name.text.trim(): h.value.text,
    },
  );

  /// Message d'erreur du brouillon, ou null s'il peut partir.
  bool _check(AccountDraft d) {
    final p = d.problem(needsPassword: widget.editing == null);
    if (p == null) return true;
    setState(() {
      _message = AppScope.of(context).strings.draftProblem(p);
      _ok = false;
    });
    return false;
  }

  Future<void> _test() async {
    if (_locked) return; // deux touchers rapides : un seul test
    final service = AppScope.of(context).accountService;
    final s = AppScope.of(context).strings;
    final d = _draft;
    if (service == null || !_check(d)) return;
    setState(() {
      _busy = true;
      _message = s.testing;
      _ok = false;
    });
    TestResult r = TestResult.unreachable;
    try {
      r = await service.testDraft(d, id: widget.editing?.id);
    } catch (_) {
      // testDraft ne lance rien ; par prudence : « injoignable »
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = s.testResult(r);
          // iPhone : un serveur de la maison injoignable vient souvent d'un accès au réseau local refusé
          if (r == TestResult.unreachable &&
              defaultTargetPlatform == TargetPlatform.iOS &&
              d.isLocalNetwork) {
            _message = '${s.testResult(r)}\n${s.localNetworkHint}';
          }
          _ok = r == TestResult.ok;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_locked) return; // deux touchers rapides : un seul compte
    final service = AppScope.of(context).accountService;
    final s = AppScope.of(context).strings;
    final d = _draft;
    if (service == null || !_check(d)) return;
    setState(() => _busy = true);
    var saved = false;
    try {
      await service.save(
        d,
        editing: widget.editing,
        keepHeaders: _headersUnread,
      );
      saved = true;
    } catch (_) {
      // jamais les valeurs du formulaire dans le message
      if (mounted) {
        setState(() {
          _message = s.saveFailed;
          _ok = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // premier lancement : l'Accueil remplace ce formulaire tout seul
    if (saved && mounted && !widget.first) Navigator.of(context).maybePop();
  }

  Future<void> _delete() async {
    final app = AppScope.of(context);
    final s = app.strings;
    final a = widget.editing!;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF232323),
        title: Text(
          s.deleteAccountQuestion(a.name),
          style: const TextStyle(
            color: LafleurColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          s.deleteAccountExplain,
          style: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              s.cancel,
              style: const TextStyle(color: LafleurColors.text),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              s.deleteAction,
              style: const TextStyle(color: _red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await app.accountService?.remove(a.id);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).strings;
    return PhoneScaffold(
      mini: false,
      header: PhoneHeader(back: widget.first ? null : s.accountsBack),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
        children: [
          if (widget.first)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                s.firstAccount,
                style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13),
              ),
            ),
          FieldLabel(s.serverType, top: 2),
          AccountTypeSegment(
            value: _type,
            onChanged: (t) => setState(() => _type = t),
          ),
          const SizedBox(height: 6),
          Text(s.subsonicServers, style: phoneHint),
          FieldLabel(s.fieldName),
          _Input(key: const ValueKey('account-name'), controller: _name),
          FieldLabel(s.fieldAddress),
          _Input(
            key: const ValueKey('account-address'),
            controller: _address,
            keyboard: TextInputType.url,
          ),
          FieldLabel(s.fieldUser),
          _Input(key: const ValueKey('account-user'), controller: _user),
          FieldLabel(s.fieldPassword),
          _Input(
            key: const ValueKey('account-password'),
            controller: _password,
            obscure: true,
            hint: widget.editing != null ? s.passwordUnchanged : null,
          ),
          FieldLabel(s.fieldHeaders),
          for (var i = 0; i < _headers.length; i++)
            Padding(
              key: ValueKey('header-$i'),
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: _Input(
                      key: ValueKey('header-$i-name'),
                      controller: _headers[i].name,
                      small: true,
                      hint: s.headerName,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _Input(
                      key: ValueKey('header-$i-value'),
                      controller: _headers[i].value,
                      small: true,
                      hint: s.headerValue,
                    ),
                  ),
                  GestureDetector(
                    key: ValueKey('header-$i-remove'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _headers.removeAt(i).dispose()),
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(8, 8, 2, 8),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Color(0xFF777777),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _headers.add(_HeaderPair())),
              child: Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                  s.addHeader,
                  style: const TextStyle(
                    color: LafleurColors.pink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              PillButton(
                label: s.testAction,
                onPressed: _locked ? null : _test,
              ),
              const SizedBox(width: 8),
              PillButton(
                label: s.save,
                primary: true,
                onPressed: _locked ? null : _save,
              ),
            ],
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _message!,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: _ok ? _green : _red,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (widget.editing != null)
            Padding(
              padding: const EdgeInsets.only(top: 36),
              child: Center(
                child: TextButton(
                  onPressed: _busy ? null : _delete,
                  child: Text(
                    s.deleteAccount,
                    style: const TextStyle(
                      color: _red,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Petit texte gris sous un champ ou en bas d'un écran.
const phoneHint = TextStyle(
  color: Color(0xFF999999),
  fontSize: 12,
  height: 1.5,
);

/// Étiquette de champ en capitales grises (NOM, ADRESSE…).
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.top = 12});
  final String text;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top, bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF999999),
        fontSize: 11,
        letterSpacing: 1,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _Input extends StatelessWidget {
  const _Input({
    super.key,
    required this.controller,
    this.obscure = false,
    this.small = false,
    this.hint,
    this.keyboard,
  });
  final TextEditingController controller;
  final bool obscure, small;
  final String? hint;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: c),
    );
    final size = small ? 12.0 : 14.0;
    return TextField(
      controller: controller,
      obscureText: obscure,
      obscuringCharacter: '•',
      autocorrect: false,
      enableSuggestions: !obscure && !small, // ni mot de passe ni en-tête
      keyboardType: keyboard,
      cursorColor: LafleurColors.pink,
      style: TextStyle(color: LafleurColors.text, fontSize: size),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(color: const Color(0xFF666666), fontSize: size),
        filled: true,
        fillColor: _fieldBg,
        contentPadding: small
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 10)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: border(const Color(0xFF333333)),
        focusedBorder: border(LafleurColors.pink),
        border: border(const Color(0xFF333333)),
      ),
    );
  }
}

/// Une case d'un [PhoneSegment] ; [enabled] false : grisée avec « bientôt ».
class SegmentOption<T> {
  const SegmentOption(this.value, this.label, {this.enabled = true});
  final T value;
  final String label;
  final bool enabled;
}

/// Choix en cases côte à côte (maquette 2) : la case choisie en rose.
class PhoneSegment<T> extends StatelessWidget {
  const PhoneSegment({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final List<SegmentOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final soon = AppScope.of(context).strings.soon;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _fieldBg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          for (final (i, o) in options.indexed) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: o.enabled ? () => onChanged(o.value) : null,
                child: Container(
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: o.value == value ? LafleurColors.pink : null,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Builder(
                    builder: (_) {
                      final style = TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: o.value == value
                            ? const Color(0xFF111111)
                            : o.enabled
                            ? const Color(0xFFBBBBBB)
                            : const Color(0xFF555555),
                      );
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              o.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style,
                            ),
                          ),
                          if (!o.enabled)
                            Text(
                              ' $soon',
                              style: style.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Subsonic seul pour l'instant ; Jellyfin et Plex grisés (plus tard).
class AccountTypeSegment extends StatelessWidget {
  const AccountTypeSegment({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final AccountType value;
  final ValueChanged<AccountType> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).strings;
    return PhoneSegment<AccountType>(
      value: value,
      onChanged: onChanged,
      options: [
        for (final t in AccountType.values)
          SegmentOption(t, s.typeName(t), enabled: t == AccountType.subsonic),
      ],
    );
  }
}
