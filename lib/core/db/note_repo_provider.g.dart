// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note_repo_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(noteRepo)
final noteRepoProvider = NoteRepoProvider._();

final class NoteRepoProvider
    extends $FunctionalProvider<NoteRepo, NoteRepo, NoteRepo>
    with $Provider<NoteRepo> {
  NoteRepoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'noteRepoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$noteRepoHash();

  @$internal
  @override
  $ProviderElement<NoteRepo> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  NoteRepo create(Ref ref) {
    return noteRepo(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NoteRepo value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NoteRepo>(value),
    );
  }
}

String _$noteRepoHash() => r'afdf33b30b02a08a46acd9f00d18a1370c752804';
