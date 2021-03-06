import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection_ext/iterables.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'package:notes_app/models.dart' show Note, NoteState;
import 'package:notes_app/styles.dart';


@immutable
abstract class NoteCommand {
  final String id;
  final String uid;


  final bool dismiss;


  const NoteCommand({
    @required this.id,
    @required this.uid,
    this.dismiss = false,
  });


  bool get isUndoable => true;


  String get message => '';


  Future<void> execute();


  Future<void> revert();
}


class NoteStateUpdateCommand extends NoteCommand {
  final NoteState from;
  final NoteState to;


  NoteStateUpdateCommand({
    @required String id,
    @required String uid,
    @required this.from,
    @required this.to,
    bool dismiss = false,
  }) : super(id: id, uid: uid, dismiss: dismiss);

  @override
  String get message {
    switch (to) {
      case NoteState.deleted:
        return 'Note moved to trash';
      case NoteState.archived:
        return 'Note archived';
      case NoteState.pinned:
        return from == NoteState.archived
            ? 'Note pinned and unarchived'
            : '';
      default:
        switch (from) {
          case NoteState.archived:
            return 'Note unarchived';
          case NoteState.deleted:
            return 'Note restored';
          default:
            return '';
        }
    }
  }

  @override
  Future<void> execute() => updateNoteState(to, id, uid);

  @override
  Future<void> revert() => updateNoteState(from, id, uid);
}


mixin CommandHandler<T extends StatefulWidget> on State<T> {

  Future<void> processNoteCommand(ScaffoldState scaffoldState, NoteCommand command) async {
    if (command == null) {
      return;
    }
    await command.execute();
    final msg = command.message;
    if (mounted && msg?.isNotEmpty == true && command.isUndoable) {
      scaffoldState?.showSnackBar(SnackBar(
        content: Text(msg),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => command.revert(),
        ),
      ));
    }
  }
}


extension NoteQuery on QuerySnapshot {

  List<Note> toNotes() => documents
      .map((d) => d.toNote())
      .nonNull
      .asList();
}


extension NoteDocument on DocumentSnapshot {

  Note toNote() => exists
      ? Note(
    id: documentID,
    title: data['title'],
    content: data['content'],
    color: _parseColor(data['color']),
    state: NoteState.values[data['state'] ?? 0],
    createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] ?? 0),
    modifiedAt: DateTime.fromMillisecondsSinceEpoch(data['modifiedAt'] ?? 0),
  )
      : null;

  Color _parseColor(num colorInt) => Color(colorInt ?? kNoteColors.first.value);
}


extension NoteStore on Note {

  Future<dynamic> saveToFireStore(String uid) async {
    final col = notesCollection(uid);
    return id == null
        ? col.add(toJson())
        : col.document(id).updateData(toJson());
  }


  Future<void> updateState(NoteState state, String uid) async => id == null
      ? updateWith(state: state) // new note
      : updateNoteState(state, id, uid);
}


CollectionReference notesCollection(String uid) => Firestore.instance.collection('notes-$uid');


DocumentReference noteDocument(String id, String uid) => notesCollection(uid).document(id);


Future<void> updateNoteState(NoteState state, String id, String uid) =>
    updateNote({'state': state?.index ?? 0}, id, uid);


Future<void> updateNote(Map<String, dynamic> data, String id, String uid) =>
    noteDocument(id, uid).updateData(data);
