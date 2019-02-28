(require 'cl)
(require 'diff)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; undo-tree.el --- Treat undo history as a tree

;;; MODIFIED SOURCE:  https://www.lawlist.com/lisp/undo-tree.el
;;;
;;; Modified and maintained by @lawlist (aka Keith David Bershatsky):  esq@lawlist.com

;;; ORIGINAL SOURCE:  https://github.com/emacsmirror/undo-tree/blob/master/undo-tree.el
;;; git clone http://www.dr-qubit.org/git/undo-tree.git
;;;
;;; Author: Toby Cubitt <toby-undo-tree@dr-qubit.org>
;;; Maintainer: Toby Cubitt <toby-undo-tree@dr-qubit.org>
;;; Version: 0.6.6
;;; Keywords: convenience, files, undo, redo, history, tree
;;; URL: http://www.dr-qubit.org/emacs.php
;;; Repository: http://www.dr-qubit.org/git/undo-tree.git

;; Copyright (C) 2009-2014  Free Software Foundation, Inc

;; This file is part of Emacs.
;;
;; This file is free software: you can redistribute it and/or modify it under
;; the terms of the GNU General Public License as published by the Free
;; Software Foundation, either version 3 of the License, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
;; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
;; more details.
;;
;; You should have received a copy of the GNU General Public License along
;; with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary by @lawlist:
;;;
;;; System Requirements:  (version-list-<= (version-to-list emacs-version) '(25 3 1))
;;;
;;; Emacs 26 (master branch) is incompatible with `undo-tree' for several reasons,
;;; which include, but are not limited to:  (1) Structs are now records in Emacs 26,
;;; whereas before they were just vectors with a special symbol in the first element.
;;; (2) @lawlist is experiencing stack overflow issues on OSX 10.6.8 when calling the
;;; `print' family of functions (bug #27571) and `read' (bug #27779) -- the trick of
;;; `ulimit -S -s unlimited` is no longer a viable workaround.
;;;
;;; This unofficial modification by @lawlist to the `undo-tree.el` library authored
;;; by Toby Cubitt adds semi-linear undo/redo support and a corresponding visualizer
;;; view accessible with `C-u C-x u` or by using the 3-way toggle with the letter `t`
;;; in the visualization buffer.  This entire library is meant to be a replacement
;;; of the stock version of `undo-tree.el` -- i.e., the stock version should be
;;; removed from the `load-path'.  In the visualization buffer, the letters `u` / `r`
;;; or `z` / `Z` are used for semi-linear undo/redo.  In the working buffer,
;;; `super-u` / `super-r` or `super-z` / `super-Z` are used for semi-linear undo/redo.
;;; Semi-linear undo/redo also work in the classic views of the visualization buffer.
;;; All previous keyboard shortcuts remain unchanged.  The mouse can be used to
;;; select semi-linear nodes or branch-point timestamps in the visualization buffer.
;;;
;;; The term `semi-linear` was chosen because the time-line is generally structured
;;; as follows:  When undoing, the movement is in an upward direction from the
;;; leaf to the branch-point and then the previous branch begins undoing from the
;;; leaf.  When redoing, the movement is in a downward direction from the branch-
;;; point to the leaf and then the next branch begins redoing from the branch-point.
;;; It is not a situation where we walk-up and back-down the same branch, or walk-
;;; down and back-up the same branch again.  If that missing feature is useful,
;;; then perhaps it could be implemented someday....
;;;
;;; In a nutshell, the classic version of undo-tree undo/redo limits a user to
;;; the active branch (skipping over inactive branches), unless the user calls
;;; `undo-tree-switch-branch' or `undo-tree-visual-switch-branch-right' or
;;; `undo-tree-visual-switch-branch-left' to select an alternative branch.  This
;;; generally means a user must pop-open the visualizer buffer to see what is going
;;; on to make a proper decision.  The new semi-linear feature is essentially
;;; `mindless` where the user can just hold down the forward/reverse button and
;;; go through every node of the tree in chronological order -- i.e., all branches
;;; and nodes are visited in the process (nothing is skipped over).
;;;
;;; The labels in the visualization buffer remain the same:  `o`, `x`, `s`, register.
;;; The branches are labeled consecutively as they are drawn with lowercase letters.
;;; The branch-points are labeled consecutively as they are drawn with uppercase
;;; letters.  The branches coming off of each branch-point are labeled with the nth
;;; numeric position of the branch -- e.g., far left is always nth 0.  The nodes of
;;; each branch are numbered consecutively commencing just after the branch-point.
;;;
;;; The features that are available in `undo-tree.el` version 0.6.6 remain the same;
;;; however, some of the functions have been consolidated and the names have changed.
;;;
;;; `undo-tree-history-save' and `undo-tree-history-restore' support input/output
;;; to/from a string or a file.  The history string/file contains three components:
;;; `buffer-file-name' (if it exists; else `nil`); SHA1 string; the `undo-tree-list'.
;;; Histories created with the unmodified stock version of `undo-tree.el` contained 2
;;; components and those previous versions are no longer supported.  Saving/exporting
;;; excludes all text-properties, yasnippet entries, and multiple-cursors entries.
;;; `read' chokes when encountering #<marker in no buffer> or #<overlay in no buffer>,
;;; that can make their way into the `undo-tree-list' when killing the visualizer
;;; buffer by brute force or when using an older yasnippet library.  [Note that the
;;; latest version of yasnippet has reportedly fixed this problem.  See pull request
;;; https://github.com/joaotavora/yasnippet/pull/804.]  Those two known situations
;;; have been dealt with programmatically.  However, there are surely other libraries
;;; that use markers and/or overlays that could make their way into the tree and new
;;; ways of dealing with those entries will be required.  If you encounter an error
;;; when performing `undo-tree-history-save', please inspect the `*Messages*` buffer
;;; for clues such as the above examples.  Inasmuch as there is now a sanity check
;;; at the tail end of `undo-tree-history-save', any problems `should` materialize
;;; before a user actually tries to restore the history.
;;;
;;; The persistent undo storage has been expanded by adding certain features borrowed
;;; from the built-in `image-dired.el' library:
;;;
;;; `undo-tree-history-autosave':  When non-nil, `undo-tree-mode' will save undo
;;;                                history to a file when a buffer is saved; and,
;;;                                restore the history file (if it exists) when
;;;                                undo-tree-mode is turned on.
;;;
;;; `undo-tree-history-alist':  Used when `undo-tree-history-storage' is 'classic.
;;;                             See the doc-string for customization tips/tricks.
;;;
;;; `undo-tree-history-directory':  Directory where history files are stored when
;;;                                `undo-tree-history-storage' is 'central.
;;;
;;; `undo-tree-history-storage':  How to store undo-tree history files.
;;;                               'classic:  See `undo-tree-history-alist'.
;;;                               'home (md5):  A folder in the HOME directory.
;;;                               'central (md5):  See `undo-tree-history-directory'.
;;;                               'local:  Create sub-directory in working directory.
;;;
;;; The following customizable variables are used to exclude major-modes, buffer
;;; names, and absolute file names from `undo-tree-mode':
;;;
;;;   -  `undo-tree-exclude-modes'
;;;   -  `undo-tree-exclude-buffers'
;;;   -  `undo-tree-exclude-files'
;;;
;;; For those users who wish to use Emacs to view the saved/exported history, be
;;; aware that the undo history is one long string, and Emacs has trouble viewing a
;;; buffer with very long lines.  `(setq-default bidi-display-reordering nil)` will
;;; help permit Emacs to view buffers with very long lines without bogging down.
;;;
;;; The primary interactive functions for undo/redo in the working buffer are:
;;;
;;;   M-x undo-tree-classic-undo
;;;   M-x undo-tree-classic-redo
;;;   M-x undo-tree-linear-undo
;;;   M-x undo-tree-linear-redo
;;;
;;; The primary interactive functions for undo/redo in the visualization buffer are:
;;;
;;;   M-x undo-tree-visual-classic-undo
;;;   M-x undo-tree-visual-classic-redo
;;;   M-x undo-tree-visual-linear-undo
;;;   M-x undo-tree-visual-linear-redo
;;;
;;; If the built-in undo amalgamation business is not to your liking, it can be
;;; disabled to permit undo boundaries after every command:
;;;
;;;   ;;; https://stackoverflow.com/a/41560712/2112489
;;;   (advice-add 'undo-auto--last-boundary-amalgamating-number :override #'ignore)
;;;
;;; GARBAGE COLLECTION:  `truncate_undo_list' in `undo.c`
;;; https://debbugs.gnu.org/cgi/bugreport.cgi?bug=27214
;;; If the `undo-limit' and `undo-strong-limit' are set too low, then garbage
;;; collection may silently truncate the `buffer-undo-list', leading to
;;; `undo-tree-transfer-list' replacing the existing `undo-tree-list' with
;;; the new tree fragment obtained from the `buffer-undo-list'.  In this
;;; circumstance, the user loses the entire undo-tree saved history!  The internal
;;; function responsible is `truncate_undo_list' in `undo.c`.  @lawlist has added a
;;; programmatic warning in `undo-tre-transfer-list' when loss of the existing
;;; `undo-tree-list' is about to occur; however, `truncate_undo_list' has already
;;; thrown something out in that case.  To avoid this situation, the user should
;;; consider increasing the default values for `undo-limit' and `undo-strong-limit'.
;;
;;; CRASHING -- SEGMENTATION FAULT:  `undo-tree-history-save'
;;; http://debbugs.gnu.org/cgi/bugreport.cgi?bug=27571
;;; The `undo-tree-list' is a lisp object consisting of nested vectors and lists,
;;; which is circular.  When the structure becomes large, Emacs will crash when
;;; printing the `undo-tree-list' with functions such as `prin1'; `print';
;;; `prin1-to-string'; etc.  The persistent history feature relies upon printing
;;; the `undo-tree-list' variable so that its value can be stored to a file.
;;; The crashing is caused because the default ulimit stack size is too low.
;;; In responding to Emacs bug report 27571, @npostavs determined that the issue
;;; can be fixed by setting the ulimit stack size with:  ulimit -S -s unlimited
;;; @lawlist has implemented this fix by starting Emacs with a bash script:
;;;     #!/bin/sh
;;;     ulimit -S -s unlimited
;;;     /Applications/Emacs.app/Contents/MacOS/Emacs &
;;; Perhaps the Emacs team will implement a built-in fix in the future.  The bug
;;; report remains open at this time, but at least we have a viable workaround.
;;; Another workaround is to truncate the `undo-tree-list' if it would exceed a
;;; specified number of nodes; e.g., 6651.  `undo-tree-transfer-list' contains a
;;; commented out call to `undo-tree-discard-history--two-of-two' which has a
;;; hard-coded limit of 6500 nodes.
;;;
;;; ERROR:  `Unrecognized entry in undo list undo-tree-canary`
;;; https://debbugs.gnu.org/cgi/bugreport.cgi?bug=16377
;;; https://debbugs.gnu.org/cgi/bugreport.cgi?bug=16523
;;; The built-in function named `primitive-undo' defined in `simple.el` was used
;;; in the original version of `undo-tree.el`.  @lawlist created a modified
;;; function named `undo-tree--primitive-undo' that serves the same purpose, but
;;; permits setting a window-point in the working buffer while a user is in a
;;; different window such as the visualization buffer.  The revised version also
;;; merely reports a problem with a message instead of throwing an error when it
;;; encounters an `undo-tree-canary' in the wrong location.  Dr. Cubitt recommends
;;; not using the undo/redo-in-region feature until he has an opportunity to fix it.
;;;
;;; The semi-linear visualization buffer view looks like this:
;;;
;;;        o-00001-a-0
;;;        20.34.55.46
;;;             |
;;;        o-br/pt-A-0
;;;        20.47.57.25
;;;        20.34.55.47
;;;         ____|_______________________________
;;;        /                                    \
;;;  o-00001-b-0                            o-00001-c-1
;;;  20.47.57.26                            20.34.55.48
;;;       |                                      |
;;;  o-00002-b-0                            o-00002-c-1
;;;  20.47.57.27                            20.34.55.49
;;;       |                                      |
;;;  o-00003-b-0                            o-00003-c-1
;;;  20.47.57.28                            20.34.55.50
;;;                                              |
;;;                                         o-00004-c-1
;;;                                         20.34.55.51
;;;                                              |
;;;                                         o-br/pt-B-1
;;;                                         21.25.32.05
;;;                                         20.35.06.89
;;;                                         20.35.02.23
;;;                                         20.34.58.43
;;;                                         20.34.55.57
;;;         _____________________________________|________________________
;;;        /            /                        |                        \
;;;  o-00001-d-0  o-00001-e-1               o-br/pt-C-2               o-00001-f-3
;;;  21.25.32.06  20.35.06.90               23.03.45.34               20.34.58.44
;;;                    |                    00.27.40.07                    |
;;;               o-00002-e-1               20.35.02.24               o-00002-f-3
;;;               20.35.06.91         ___________|___________         20.34.58.45
;;;                    |             /           |           \             |
;;;               o-00003-e-1  o-00001-g-0  o-00001-h-1  o-00001-i-2  o-00003-f-3
;;;               20.35.06.92  23.03.45.35  00.27.40.08  20.35.02.25  20.34.58.46
;;;                    |            |            |            |            |
;;;               o-00004-e-1  x-00002-g-0  o-00002-h-1  o-00002-i-2  o-00004-f-3
;;;               20.35.06.93  23:03:45:36  00.27.44.51  20.35.02.26  20.34.58.47
;;;                    |                                      |            |
;;;               o-00005-e-1                            o-00003-i-2  o-00005-f-3
;;;               20.35.06.94                            20.35.02.27  20.34.58.48
;;;                    |                                      |            |
;;;               o-00006-e-1                            o-00004-i-2  o-00006-f-3
;;;               20.35.06.95                            20.35.02.28  20.34.58.49
;;;                    |                                      |            |
;;;               o-00007-e-1                            o-00005-i-2  o-00007-f-3
;;;               20.35.06.96                            20.35.02.29  20.34.58.50
;;;                    |                                      |            |
;;;               o-00008-e-1                            o-00006-i-2  o-00008-f-3
;;;               20.35.06.97                            20.35.02.30  20.34.58.51
;;;
;;; To check for updates, please visit the source-code of the link listed at the
;;; top and also review the `Change Log` at the bottom.
;;;
;;; Bug reports and feature requests may be submitted via email to the address at
;;; the top.  Essentially, if it breaks in half, I can guarantee that you will
;;; have 2 pieces that may not necessarily be the same size.  :)  That being said,
;;; I will certainly make efforts to fix any problem that may arise relating to
;;; the semi-linear undo/redo feature.  A step 1-2-3 recipe starting from emacs -q
;;; would be very helpful so that @lawlist can observe the same behavior described
;;; in the bug report.  Here is an example to get you started:
;;;
;;; 1.  In an internet browser, visit: https://www.lawlist.com/lisp/undo-tree.el
;;;
;;;     Select/highlight all and copy everything to the clipboard.
;;;
;;; 2.  Launch Emacs without any user settings whatsoever:  emacs -q
;;;
;;;     If possible, please use the latest stable public release of Emacs.
;;;     @lawlist is using the GUI version of Emacs 25.2.1 on OSX.
;;;
;;; 3.  Switch to the `*scratch*` buffer.
;;;
;;; 4.  Paste the entire contents of the clipboard into the `*scratch*` buffer.
;;;
;;; 5.  M-x eval-buffer RET
;;;
;;; 6.  M-x eval-expression RET (setq undo-tree-history-autosave t) RET
;;;
;;; 7.  M-x undo-tree-mode RET
;;;
;;;     The mode-line indicates `UT`, meaning that `undo-tree-mode' is active.
;;;
;;; 8.  M-x save-buffer RET
;;;
;;;     @lawlist chose to save the file to his desktop with the name `foo`, and
;;;     also chose to overwrite the file if it already existed; i.e., `y`.
;;;
;;;     Look at the lower left-hand side of the mode-line and notice that it
;;;     indicates an unmodified state; i.e., U:--- foo ....
;;;
;;; 9.  M-x undo-tree-classic-undo RET
;;;
;;;     Look at the lower left-hand side of the mode-line and notice that it
;;;     indicates we have returned to a modified state; i.e., U:**- foo ....
;;;
;;; 10. M-x undo-tree-classic-undo RET
;;;
;;;     The `undo-tree' library that we had previously pasted to the `*scratch*`
;;;     buffer should now be completely undone; i.e., removed.
;;;
;;; 11. M-x undo-tree-classic-undo RET
;;;
;;;     The buffer should be completely empty at this point; i.e., the initial
;;;     `*scratch*` message has been removed.
;;;
;;; 12. M-x undo-tree-classic-undo RET
;;;
;;;     The following `user-error' appears:
;;;
;;;       `user-error:  undo-tree--undo-or-redo:  No further undo information.`
;;;
;;;     This is exactly the behavior that @lawlist expected would happen, so
;;;     everything up to this point appears to be working correctly.

;;; Written by @aiPh8Se on Reddit.
;;; https://www.reddit.com/r/emacs/comments/6yzwic/how_emacs_undo_works/?ref=share&ref_source=link
;;; 
;;; There are two undo commands, `undo' and `undo-only'. `undo-only' will only undo,
;;; skipping undoing undos (redoing).
;;; 
;;; The rules:
;;; 
;;;     All changes, including undos, get added to the front of the undo chain.
;;;     `undo' moves back one state along the undo chain.
;;;     `undo-only' moves back one state along the temporal axis.
;;;     `undo-only' always move backward along the temporal axis.
;;;     `undo' moves in the opposite direction along the temporal axis as the change it is undoing.
;;; 
;;; I encourage you to follow along with the example. Open up *scratch* and bind
;;; `undo-only' to an easy to press key; you don't want to use `M-x` for this.
;;; 
;;; First, insert some text
;;; 
;;;             A  B  C
;;;  Insert! o--o--o--o
;;; 
;;; Each node represents a buffer state. Each buffer state will be labeled with a letter.
;;; For convenience, type a `RET` to move to state A. The `RET` is an easy way to make Emacs
;;; set a break in the undo chain; otherwise Emacs will group contiguous inserts into one
;;; "state". Also, this state A is actually two states, the "inserted a" and "inserted RET"
;;; states. In this example, each undo will actually be two undos, one to undo the `RET` and
;;; one to undo the letter.
;;; 
;;; After following the above, your buffer should look like this:
;;; 
;;; a
;;; b
;;; c
;;; 
;;; Next, undo twice:
;;; 
;;;             A  B  C
;;;  Insert! o--o--o--o  Undo!
;;;                  /
;;;                 /
;;;                o
;;;               /
;;;              /
;;;             o
;;; 
;;; You are now back at state A. Note how the undo chain is presented here. The undos have
;;; been added to the end of the undo chain, however, the chain is now going backward temporally.
;;; We type some more:
;;; 
;;;             A  B  C
;;;  Insert! o--o--o--o  Undo!
;;;                  /
;;;                 /
;;;                o
;;;               /
;;;              / D  E
;;;    Insert!  o--o--o  Undo!
;;; 
;;; Still simple. We keep going:
;;; 
;;;             A  B  C
;;;  Insert! o--o--o--o  Undo!
;;;                  /
;;;                 /
;;;                o
;;;               /
;;;              / D  E
;;;    Insert!  o--o--o  Undo!
;;;                  /
;;;                 / F  G  H
;;;       Insert!  o--o--o--o  Undo!
;;;                        /
;;;                       / I  J
;;;             Insert!  o--o--o
;;; 
;;; It's getting complex now; we'll start calling `undo-only' now:
;;; 
;;;             A  B  C
;;;  Insert! o--o--o--o  Undo!
;;;                  /
;;;                 /
;;;                o
;;;               /
;;;              / D  E
;;;    Insert!  o--o--o  Undo!
;;;                  /
;;;                 / F  G  H
;;;       Insert!  o--o--o--o  Undo!
;;;                        /
;;;                       / I  J
;;;             Insert!  o--o--o  `undo-only'
;;;                           /
;;;                   F  G   /
;;;                   o--o--o
;;; 
;;; Our first `undo-only' goes back one state to state I. So far so good.
;;; 
;;; Our second `undo-only' goes back one state to state G. So far so good.
;;; 
;;; Our third `undo-only' goes back three states to state F. However, we only went back
;;; only one state "temporally": we skipped all intervening undo/redo pairs.
;;; 
;;; We keep going.
;;; 
;;;             A  B  C
;;;  Insert! o--o--o--o  Undo!
;;;                  /
;;;                 /
;;;                o
;;;               /
;;;              / D  E
;;;    Insert!  o--o--o  Undo!
;;;                  /
;;;                 / F  G  H
;;;       Insert!  o--o--o--o  Undo!
;;;                        /
;;;                       / I  J
;;;             Insert!  o--o--o  `undo-only'
;;;                           /
;;;                D  F  G   /
;;;                o--o--o--o
;;;               /
;;;             A/
;;;             o
;;; 
;;; Now we're all the way back to state A.  With `undo', we would have had to traverse every
;;; single state (count them, there's a lot), but with `undo-only', it only took five.
;;; 
;;; Now for the final stretch. We insert a few more fresh states:
;;; 
;;;             A  B  C
;;;  Insert! o--o--o--o  Undo!
;;;                  /
;;;                 /
;;;                o
;;;               /
;;;              / D  E
;;;    Insert!  o--o--o  Undo!
;;;                  /
;;;                 / F  G  H
;;;       Insert!  o--o--o--o  Undo!
;;;                        /
;;;                       / I  J
;;;             Insert!  o--o--o  `undo-only'
;;;                           /
;;;                D  F  G   /
;;;                o--o--o--o
;;;               /
;;;             A/ K  L
;;;    Insert!  o--o--o
;;; 
;;; And we undo a whole bunch:
;;; 
;;;             A  B  C
;;;  Insert! o--o--o--o  Undo!
;;;                  /
;;;                 /
;;;                o
;;;               /
;;;              / D  E
;;;    Insert!  o--o--o  Undo!
;;;                  /
;;;                 / F  G  H
;;;       Insert!  o--o--o--o  Undo!
;;;                        /
;;;                       / I  J
;;;             Insert!  o--o--o  `undo-only'
;;;                           /
;;;                D  F  G   /
;;;                o--o--o--o
;;;               /
;;;             A/ K  L
;;;    Insert!  o--o--o  Undo!
;;;                  /
;;;                 /
;;;                o
;;;               /
;;;              / D  F  G  I  J
;;; (continue)  o--o--o--o--o--o
;;; 
;;; Okay, what happened here? We undid the new states we added, and those undo actions
;;; get added going backward temporally. After that though, we started undoing undos.
;;; These undo changes get added with the reverse temporality as the original changes,
;;; so these undo changes are going forward temporally. If you did `undo-only' at this
;;; point, you would undo these changes.
;;; 
;;; (But wait, aren't these changes undo changes? `undo-only' doesn't undo undos, right?
;;; Well, these changes are actually undos of undos, so they're actually redos, not undos,
;;; hence why they move forward temporally.)
;;; 
;;; That's it for the example. Keep in mind however that this "undo chain" is just a concept
;;; to help understand how undo works. What Emacs actually stores is `buffer-undo-list'.
;;; You can check it out with describe-variable.
;;; 
;;; If you have been following along with the example, the state of `buffer-undo-list'
;;; should be like below. I have annotated it with points from the undo chain diagrams.
;;; 
;;; '(
;;;   nil
;;;   (12 . 13)
;;;   nil
;;;   (11 . 12)                             ;Redo insert j
;;;   nil
;;;   (10 . 11)
;;;   nil
;;;   (9 . 10)                              ;Redo insert i
;;;   nil
;;;   (8 . 9)
;;;   nil
;;;   (7 . 8)                               ;Redo insert g
;;;   nil
;;;   (6 . 7)
;;;   nil
;;;   (5 . 6)                               ;Redo insert f
;;;   nil
;;;   (4 . 5)                               ;Redo insert newline
;;;   nil
;;;   (3 . 4)                               ;Redo insert d
;;;   nil
;;;   ("k" . 3)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker
;;;    (moves after insertion)
;;;    at 13 in tmp-undo> . 1)
;;;   nil
;;;   ("\n" . 4)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker
;;;    (moves after insertion)
;;;    at 13 in tmp-undo> . 1)
;;;   (#<marker
;;;    (moves after insertion)
;;;    at 13 in tmp-undo> . 1)
;;;   nil
;;;   ("l" . 5)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker
;;;    (moves after insertion)
;;;    at 13 in tmp-undo> . 1)
;;;   nil
;;;   ("\n" . 6)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker
;;;    (moves after insertion)
;;;    at 13 in tmp-undo> . 1)
;;;   (#<marker
;;;    (moves after insertion)
;;;    at 13 in tmp-undo> . 1)
;;;   nil
;;;   (6 . 7)
;;;   nil
;;;   (5 . 6)                               ;Insert l
;;;   nil
;;;   (4 . 5)
;;;   nil
;;;   (3 . 4)                               ;Insert k
;;;   nil
;;;   ("d" . 3)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   nil
;;;   ("\n" . 4)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   nil
;;;   ("f" . 5)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   nil
;;;   ("\n" . 6)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   nil
;;;   ("g" . 7)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   nil
;;;   ("\n" . 8)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   nil
;;;   ("i" . 9)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   nil
;;;   ("\n" . 10)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   nil
;;;   ("j" . 11)                            ;Undo-only insert j
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   nil
;;;   ("\n" . 12)
;;;   (#<marker
;;;    (moves after insertion)
;;;    at 12 in tmp-undo> . 1)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   nil
;;;   (12 . 13)
;;;   nil
;;;   (11 . 12)                             ;Insert j
;;;   nil
;;;   (10 . 11)
;;;   nil
;;;   (9 . 10)                              ;Insert i
;;;   nil
;;;   ("h" . 9)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   nil
;;;   ("\n" . 10)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   nil
;;;   (10 . 11)
;;;   nil
;;;   (9 . 10)                              ;Insert h
;;;   nil
;;;   (8 . 9)
;;;   nil
;;;   (7 . 8)                               ;Insert g
;;;   nil
;;;   (6 . 7)
;;;   nil
;;;   (5 . 6)                               ;Insert f
;;;   nil
;;;   ("e" . 5)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker
;;;    (moves after insertion)
;;;    at 13 in tmp-undo> . 1)
;;;   nil
;;;   ("\n" . 6)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker
;;;    (moves after insertion)
;;;    at 13 in tmp-undo> . 1)
;;;   (#<marker
;;;    (moves after insertion)
;;;    at 13 in tmp-undo> . 1)
;;;   nil
;;;   (6 . 7)
;;;   nil
;;;   (5 . 6)                               ;Insert e
;;;   nil
;;;   (4 . 5)
;;;   nil
;;;   (3 . 4)                               ;Insert d
;;;   nil
;;;   ("b" . 3)                             ;Undo insert b
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker
;;;    (moves after insertion)
;;;    at 13 in tmp-undo> . 1)
;;;   nil
;;;   ("\n" . 4)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker
;;;    (moves after insertion)
;;;    at 13 in tmp-undo> . 1)
;;;   (#<marker
;;;    (moves after insertion)
;;;    at 13 in tmp-undo> . 1)
;;;   nil
;;;   ("c" . 5)                             ;Undo insert c
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker
;;;    (moves after insertion)
;;;    at 13 in tmp-undo> . 1)
;;;   nil
;;;   ("\n" . 6)
;;;   (#<marker at 12 in tmp-undo> . -1)
;;;   (#<marker
;;;    (moves after insertion)
;;;    at 13 in tmp-undo> . 1)
;;;   (#<marker
;;;    (moves after insertion)
;;;    at 13 in tmp-undo> . 1)
;;;   nil
;;;   (6 . 7)
;;;   nil
;;;   (5 . 6)                               ;Insert c
;;;   nil
;;;   (4 . 5)
;;;   nil
;;;   (3 . 4)                               ;Insert b
;;;   nil
;;;   (2 . 3)                               ;Insert newline
;;;   nil
;;;   (1 . 2)                             ;Insert a
;;;   (t . 0)                             ;Buffer before modification time
;;;   )
;;; 
;;; Finally finally, undo records for undos (redos) are stored in `undo-equiv-table'.
;;; Again, feel free to check it out.

;;; Commentary by Toby Cubitt:
;;
;; Emacs has a powerful undo system. Unlike the standard undo/redo system in
;; most software, it allows you to recover *any* past state of a buffer
;; (whereas the standard undo/redo system can lose past states as soon as you
;; redo). However, this power comes at a price: many people find Emacs' undo
;; system confusing and difficult to use, spawning a number of packages that
;; replace it with the less powerful but more intuitive undo/redo system.
;;
;; Both the loss of data with standard undo/redo, and the confusion of Emacs'
;; undo, stem from trying to treat undo history as a linear sequence of
;; changes. It's not. The `undo-tree-mode' provided by this package replaces
;; Emacs' undo system with a system that treats undo history as what it is: a
;; branching tree of changes. This simple idea allows the more intuitive
;; behaviour of the standard undo/redo system to be combined with the power of
;; never losing any history. An added side bonus is that undo history can in
;; some cases be stored more efficiently, allowing more changes to accumulate
;; before Emacs starts discarding history.
;;
;; The only downside to this more advanced yet simpler undo system is that it
;; was inspired by Vim. But, after all, most successful religions steal the
;; best ideas from their competitors!
;;
;;
;; Installation
;; ============
;;
;; This package has only been tested with Emacs versions 24 and CVS. It should
;; work in Emacs versions 22 and 23 too, but will not work without
;; modifications in earlier versions of Emacs.
;;
;; To install `undo-tree-mode', make sure this file is saved in a directory in
;; your `load-path', and add the line:
;;
;;   (require 'undo-tree)
;;
;; to your .emacs file. Byte-compiling undo-tree.el is recommended (e.g. using
;; "M-x byte-compile-file" from within emacs).
;;
;; If you want to replace the standard Emacs' undo system with the
;; `undo-tree-mode' system in all buffers, you can enable it globally by
;; adding:
;;
;;   (global-undo-tree-mode)
;;
;; to your .emacs file.
;;
;;
;; Quick-Start
;; ===========
;;
;; If you're the kind of person who likes to jump in the car and drive,
;; without bothering to first figure out whether the button on the left dips
;; the headlights or operates the ejector seat (after all, you'll soon figure
;; it out when you push it), then here's the minimum you need to know:
;;
;; `undo-tree-mode' and `global-undo-tree-mode'
;;   Enable undo-tree mode (either in the current buffer or globally).
;;
;; C-_  C-/  (`undo-tree-classic-undo')
;;   Undo changes.
;;
;; M-_  C-?  (`undo-tree-classic-redo')
;;   Redo changes.
;;
;; `undo-tree-switch-branch'
;;   Switch undo-tree branch.
;;   (What does this mean? Better press the button and see!)
;;
;; C-x u  (`undo-tree-visual')
;;   Visualize the undo tree.
;;   (Better try pressing this button too!)
;;
;; C-x r u  (`undo-tree-save-state-to-register')
;;   Save current buffer state to register.
;;
;; C-x r U  (`undo-tree-restore-state-from-register')
;;   Restore buffer state from register.
;;
;;
;;
;; In the undo-tree visualizer:
;;
;; <up>  p  C-p  (`undo-tree-visual-classic-undo')
;;   Undo changes.
;;
;; <down>  n  C-n  (`undo-tree-visual-classic-redo')
;;   Redo changes.
;;
;; <left>  b  C-b  (`undo-tree-visual-switch-branch-left')
;;   Switch to previous undo-tree branch.
;;
;; <right>  f  C-f  (`undo-tree-visual-switch-branch-right')
;;   Switch to next undo-tree branch.
;;
;; C-<up>  M-{  (`undo-tree-visual-undo-to-x')
;;   Undo changes up to last branch point.
;;
;; C-<down>  M-}  (`undo-tree-visual-redo-to-x')
;;   Redo changes down to next branch point.
;;
;; <mouse-1>  (`undo-tree-visual-mouse-set')
;;   Set state to node at mouse click.
;;
;; t  (`undo-tree-visual-toggle-timestamps')
;;   Toggle display of time-stamps.
;;
;; d  (`undo-tree-visual-toggle-diff')
;;   Toggle diff display.
;;
;; s  (`undo-tree-visual-selection-mode')
;;   Toggle keyboard selection mode.
;;
;; q  (`undo-tree-visual-quit')
;;   Quit undo-tree-visual.
;;
;; C-q  (`undo-tree-visual-abort')
;;   Abort undo-tree-visual.
;;
;; ,  <
;;   Scroll left.
;;
;; .  >
;;   Scroll right.
;;
;; <pgup>  M-v
;;   Scroll up.
;;
;; <pgdown>  C-v
;;   Scroll down.
;;
;;
;;
;; In visualizer selection mode:
;;
;; <up>  p  C-p  (`undo-tree-visual-select-previous')
;;   Select previous node.
;;
;; <down>  n  C-n  (`undo-tree-visual-select-next')
;;   Select next node.
;;
;; <left>  b  C-b  (`undo-tree-visual-select-left')
;;   Select left sibling node.
;;
;; <right>  f  C-f  (`undo-tree-visual-select-right')
;;   Select right sibling node.
;;
;; <pgup>  M-v
;;   Select node 10 above.
;;
;; <pgdown>  C-v
;;   Select node 10 below.
;;
;; <enter>  (`undo-tree-visual-set')
;;   Set state to selected node and exit selection mode.
;;
;; s  (`undo-tree-visual-mode')
;;   Exit selection mode.
;;
;; t  (`undo-tree-visual-toggle-timestamps')
;;   Toggle display of time-stamps.
;;
;; d  (`undo-tree-visual-toggle-diff')
;;   Toggle diff display.
;;
;; q  (`undo-tree-visual-quit')
;;   Quit undo-tree-visual.
;;
;; C-q  (`undo-tree-visual-abort')
;;   Abort undo-tree-visual.
;;
;; ,  <
;;   Scroll left.
;;
;; .  >
;;   Scroll right.
;;
;;
;;
;; Persistent undo history:
;;
;; Note: Requires Emacs version 24.3 or higher.
;;
;; `undo-tree-history-autosave' (variable)
;;    automatically save and restore undo-tree history along with buffer
;;    (disabled by default)
;;
;; `undo-tree-history-save' (command)
;;    manually save undo history to file
;;
;; `undo-tree-history-restore' (command)
;;    manually load undo history from file
;;
;;
;;
;; Compressing undo history:
;;
;;   Undo history files cannot grow beyond the maximum undo tree size, which
;;   is limited by `undo-tree--undo-limit', `undo-tree--undo-strong-limit' and
;;   `undo-tree--undo-outer-limit'. Nevertheless, undo history files can grow quite
;;   large. If you want to automatically compress undo history, add the
;;   following advice to your .emacs file (replacing ".gz" with the filename
;;   extension of your favourite compression algorithm):
;;
;;   (lawlist-defadvice undo-tree-history-classic-filename
;;     (after undo-tree activate)
;;     (setq ad-return-value (concat ad-return-value ".gz")))
;;
;;
;;
;;
;; Undo Systems
;; ============
;;
;; To understand the different undo systems, it's easiest to consider an
;; example. Imagine you make a few edits in a buffer. As you edit, you
;; accumulate a history of changes, which we might visualize as a string of
;; past buffer states, growing downwards:
;;
;;                                o  (initial buffer state)
;;                                |
;;                                |
;;                                o  (first edit)
;;                                |
;;                                |
;;                                o  (second edit)
;;                                |
;;                                |
;;                                x  (current buffer state)
;;
;;
;; Now imagine that you undo the last two changes. We can visualize this as
;; rewinding the current state back two steps:
;;
;;                                o  (initial buffer state)
;;                                |
;;                                |
;;                                x  (current buffer state)
;;                                |
;;                                |
;;                                o
;;                                |
;;                                |
;;                                o
;;
;;
;; However, this isn't a good representation of what Emacs' undo system
;; does. Instead, it treats the undos as *new* changes to the buffer, and adds
;; them to the history:
;;
;;                                o  (initial buffer state)
;;                                |
;;                                |
;;                                o  (first edit)
;;                                |
;;                                |
;;                                o  (second edit)
;;                                |
;;                                |
;;                                x  (buffer state before undo)
;;                                |
;;                                |
;;                                o  (first undo)
;;                                |
;;                                |
;;                                x  (second undo)
;;
;;
;; Actually, since the buffer returns to a previous state after an undo,
;; perhaps a better way to visualize it is to imagine the string of changes
;; turning back on itself:
;;
;;        (initial buffer state)  o
;;                                |
;;                                |
;;                  (first edit)  o  x  (second undo)
;;                                |  |
;;                                |  |
;;                 (second edit)  o  o  (first undo)
;;                                | /
;;                                |/
;;                                o  (buffer state before undo)
;;
;; Treating undos as new changes might seem a strange thing to do. But the
;; advantage becomes clear as soon as we imagine what happens when you edit
;; the buffer again. Since you've undone a couple of changes, new edits will
;; branch off from the buffer state that you've rewound to. Conceptually, it
;; looks like this:
;;
;;                                o  (initial buffer state)
;;                                |
;;                                |
;;                                o
;;                                |\
;;                                | \
;;                                o  x  (new edit)
;;                                |
;;                                |
;;                                o
;;
;; The standard undo/redo system only lets you go backwards and forwards
;; linearly. So as soon as you make that new edit, it discards the old
;; branch. Emacs' undo just keeps adding changes to the end of the string. So
;; the undo history in the two systems now looks like this:
;;
;;            Undo/Redo:                      Emacs' undo
;;
;;               o                                o
;;               |                                |
;;               |                                |
;;               o                                o  o
;;               .\                               |  |\
;;               . \                              |  | \
;;               .  x  (new edit)                 o  o  |
;;   (discarded  .                                | /   |
;;     branch)   .                                |/    |
;;               .                                o     |
;;                                                      |
;;                                                      |
;;                                                      x  (new edit)
;;
;; Now, what if you change your mind about those undos, and decide you did
;; like those other changes you'd made after all? With the standard undo/redo
;; system, you're lost. There's no way to recover them, because that branch
;; was discarded when you made the new edit.
;;
;; However, in Emacs' undo system, those old buffer states are still there in
;; the undo history. You just have to rewind back through the new edit, and
;; back through the changes made by the undos, until you reach them. Of
;; course, since Emacs treats undos (even undos of undos!) as new changes,
;; you're really weaving backwards and forwards through the history, all the
;; time adding new changes to the end of the string as you go:
;;
;;                       o
;;                       |
;;                       |
;;                       o  o     o  (undo new edit)
;;                       |  |\    |\
;;                       |  | \   | \
;;                       o  o  |  |  o  (undo the undo)
;;                       | /   |  |  |
;;                       |/    |  |  |
;;      (trying to get   o     |  |  x  (undo the undo)
;;       to this state)        | /
;;                             |/
;;                             o
;;
;; So far, this is still reasonably intuitive to use. It doesn't behave so
;; differently to standard undo/redo, except that by going back far enough you
;; can access changes that would be lost in standard undo/redo.
;;
;; However, imagine that after undoing as just described, you decide you
;; actually want to rewind right back to the initial state. If you're lucky,
;; and haven't invoked any command since the last undo, you can just keep on
;; undoing until you get back to the start:
;;
;;      (trying to get   o              x  (got there!)
;;       to this state)  |              |
;;                       |              |
;;                       o  o     o     o  (keep undoing)
;;                       |  |\    |\    |
;;                       |  | \   | \   |
;;                       o  o  |  |  o  o  (keep undoing)
;;                       | /   |  |  | /
;;                       |/    |  |  |/
;;      (already undid   o     |  |  o  (got this far)
;;       to this state)        | /
;;                             |/
;;                             o
;;
;; But if you're unlucky, and you happen to have moved the point (say) after
;; getting to the state labelled "got this far", then you've "broken the undo
;; chain". Hold on to something solid, because things are about to get
;; hairy. If you try to undo now, Emacs thinks you're trying to undo the
;; undos! So to get back to the initial state you now have to rewind through
;; *all* the changes, including the undos you just did:
;;
;;      (trying to get   o                          x  (finally got there!)
;;       to this state)  |                          |
;;                       |                          |
;;                       o  o     o     o     o     o
;;                       |  |\    |\    |\    |\    |
;;                       |  | \   | \   | \   | \   |
;;                       o  o  |  |  o  o  |  |  o  o
;;                       | /   |  |  | /   |  |  | /
;;                       |/    |  |  |/    |  |  |/
;;      (already undid   o     |  |  o<.   |  |  o
;;       to this state)        | /     :   | /
;;                             |/      :   |/
;;                             o       :   o
;;                                     :
;;                             (got this far, but
;;                              broke the undo chain)
;;
;; Confused?
;;
;; In practice you can just hold down the undo key until you reach the buffer
;; state that you want. But whatever you do, don't move around in the buffer
;; to *check* that you've got back to where you want! Because you'll break the
;; undo chain, and then you'll have to traverse the entire string of undos
;; again, just to get back to the point at which you broke the
;; chain. Undo-in-region and commands such as `undo-only' help to make using
;; Emacs' undo a little easier, but nonetheless it remains confusing for many
;; people.
;;
;;
;; So what does `undo-tree-mode' do? Remember the diagram we drew to represent
;; the history we've been discussing (make a few edits, undo a couple of them,
;; and edit again)? The diagram that conceptually represented our undo
;; history, before we started discussing specific undo systems? It looked like
;; this:
;;
;;                                o  (initial buffer state)
;;                                |
;;                                |
;;                                o
;;                                |\
;;                                | \
;;                                o  x  (current state)
;;                                |
;;                                |
;;                                o
;;
;; Well, that's *exactly* what the undo history looks like to
;; `undo-tree-mode'.  It doesn't discard the old branch (as standard undo/redo
;; does), nor does it treat undos as new changes to be added to the end of a
;; linear string of buffer states (as Emacs' undo does). It just keeps track
;; of the tree of branching changes that make up the entire undo history.
;;
;; If you undo from this point, you'll rewind back up the tree to the previous
;; state:
;;
;;                                o
;;                                |
;;                                |
;;                                x  (undo)
;;                                |\
;;                                | \
;;                                o  o
;;                                |
;;                                |
;;                                o
;;
;; If you were to undo again, you'd rewind back to the initial state. If on
;; the other hand you redo the change, you'll end up back at the bottom of the
;; most recent branch:
;;
;;                                o  (undo takes you here)
;;                                |
;;                                |
;;                                o  (start here)
;;                                |\
;;                                | \
;;                                o  x  (redo takes you here)
;;                                |
;;                                |
;;                                o
;;
;; So far, this is just like the standard undo/redo system. But what if you
;; want to return to a buffer state located on a previous branch of the
;; history? Since `undo-tree-mode' keeps the entire history, you simply need
;; to tell it to switch to a different branch, and then redo the changes you
;; want:
;;
;;                                o
;;                                |
;;                                |
;;                                o  (start here, but switch
;;                                |\  to the other branch)
;;                                | \
;;                        (redo)  o  o
;;                                |
;;                                |
;;                        (redo)  x
;;
;; Now you're on the other branch, if you undo and redo changes you'll stay on
;; that branch, moving up and down through the buffer states located on that
;; branch. Until you decide to switch branches again, of course.
;;
;; Real undo trees might have multiple branches and sub-branches:
;;
;;                                o
;;                            ____|______
;;                           /           \
;;                          o             o
;;                      ____|__         __|
;;                     /    |  \       /   \
;;                    o     o   o     o     x
;;                    |               |
;;                   / \             / \
;;                  o   o           o   o
;;
;; Trying to imagine what Emacs' undo would do as you move about such a tree
;; will likely frazzle your brain circuits! But in `undo-tree-mode', you're
;; just moving around this undo history tree. Most of the time, you'll
;; probably only need to stay on the most recent branch, in which case it
;; behaves like standard undo/redo, and is just as simple to understand. But
;; if you ever need to recover a buffer state on a different branch, the
;; possibility of switching between branches and accessing the full undo
;; history is still there.
;;
;;
;;
;; The Undo-Tree Visualizer
;; ========================
;;
;; Actually, it gets better. You don't have to imagine all these tree
;; diagrams, because `undo-tree-mode' includes an undo-tree visualizer which
;; draws them for you! In fact, it draws even better diagrams: it highlights
;; the node representing the current buffer state, it highlights the current
;; branch, and you can toggle the display of time-stamps (by hitting "t") and
;; a diff of the undo changes (by hitting "d"). (There's one other tiny
;; difference: the visualizer puts the most recent branch on the left rather
;; than the right.)
;;
;; Bring up the undo tree visualizer whenever you want by hitting "C-x u".
;;
;; In the visualizer, the usual keys for moving up and down a buffer instead
;; move up and down the undo history tree (e.g. the up and down arrow keys, or
;; "C-n" and "C-p"). The state of the "parent" buffer (the buffer whose undo
;; history you are visualizing) is updated as you move around the undo tree in
;; the visualizer. If you reach a branch point in the visualizer, the usual
;; keys for moving forward and backward in a buffer instead switch branch
;; (e.g. the left and right arrow keys, or "C-f" and "C-b").
;;
;; Clicking with the mouse on any node in the visualizer will take you
;; directly to that node, resetting the state of the parent buffer to the
;; state represented by that node.
;;
;; You can also select nodes directly using the keyboard, by hitting "s" to
;; toggle selection mode. The usual motion keys now allow you to move around
;; the tree without changing the parent buffer. Hitting <enter> will reset the
;; state of the parent buffer to the state represented by the currently
;; selected node.
;;
;; It can be useful to see how long ago the parent buffer was in the state
;; represented by a particular node in the visualizer. Hitting "t" in the
;; visualizer toggles the display of time-stamps for all the nodes. (Note
;; that, because of the way `undo-tree-mode' works, these time-stamps may be
;; somewhat later than the true times, especially if it's been a long time
;; since you last undid any changes.)
;;
;; To get some idea of what changes are represented by a given node in the
;; tree, it can be useful to see a diff of the changes. Hit "d" in the
;; visualizer to toggle a diff display. This normally displays a diff between
;; the current state and the previous one, i.e. it shows you the changes that
;; will be applied if you undo (move up the tree). However, the diff display
;; really comes into its own in the visualizer's selection mode (see above),
;; where it instead shows a diff between the current state and the currently
;; selected state, i.e. it shows you the changes that will be applied if you
;; reset to the selected state.
;;
;; (Note that the diff is generated by the Emacs `diff' command, and is
;; displayed using `diff-mode'. See the corresponding customization groups if
;; you want to customize the diff display.)
;;
;; Finally, hitting "q" will quit the visualizer, leaving the parent buffer in
;; whatever state you ended at. Hitting "C-q" will abort the visualizer,
;; returning the parent buffer to whatever state it was originally in when the
;; visualizer was invoked.
;;
;;
;;
;; Undo-in-Region
;; ==============
;;
;; Emacs allows a very useful and powerful method of undoing only selected
;; changes: when a region is active, only changes that affect the text within
;; that region will be undone. With the standard Emacs undo system, changes
;; produced by undoing-in-region naturally get added onto the end of the
;; linear undo history:
;;
;;                       o
;;                       |
;;                       |  x  (second undo-in-region)
;;                       o  |
;;                       |  |
;;                       |  o  (first undo-in-region)
;;                       o  |
;;                       | /
;;                       |/
;;                       o
;;
;; You can of course redo these undos-in-region as usual, by undoing the
;; undos:
;;
;;                       o
;;                       |
;;                       |  o_
;;                       o  | \
;;                       |  |  |
;;                       |  o  o  (undo the undo-in-region)
;;                       o  |  |
;;                       | /   |
;;                       |/    |
;;                       o     x  (undo the undo-in-region)
;;
;;
;; In `undo-tree-mode', undo-in-region works much the same way: when there's
;; an active region, undoing only undoes changes that affect that region. In
;; `undo-tree-mode', redoing when there's an active region similarly only
;; redoes changes that affect that region.
;;
;; However, the way these undo- and redo-in-region changes are recorded in the
;; undo history is quite different. The good news is, you don't need to
;; understand this to use undo- and redo-in-region in `undo-tree-mode' - just
;; go ahead and use them! They'll probably work as you expect. But if you're
;; masochistic enough to want to understand conceptually what's happening to
;; the undo tree as you undo- and redo-in-region, then read on...
;;
;;
;; Undo-in-region creates a new branch in the undo history. The new branch
;; consists of an undo step that undoes some of the changes that affect the
;; current region, and another step that undoes the remaining changes needed
;; to rejoin the previous undo history.
;;
;;      Previous undo history                Undo-in-region
;;
;;               o                                o
;;               |                                |
;;               |                                |
;;               |                                |
;;               o                                o
;;               |                                |
;;               |                                |
;;               |                                |
;;               o                                o_
;;               |                                | \
;;               |                                |  x  (undo-in-region)
;;               |                                |  |
;;               x                                o  o
;;
;; As long as you don't change the active region after undoing-in-region,
;; continuing to undo-in-region extends the new branch, pulling more changes
;; that affect the current region into an undo step immediately above your
;; current location in the undo tree, and pushing the point at which the new
;; branch is attached further up the tree:
;;
;;      First undo-in-region                 Second undo-in-region
;;
;;               o                                o
;;               |                                |
;;               |                                |
;;               |                                |
;;               o                                o_
;;               |                                | \
;;               |                                |  x  (undo-in-region)
;;               |                                |  |
;;               o_                               o  |
;;               | \                              |  |
;;               |  x                             |  o
;;               |  |                             |  |
;;               o  o                             o  o
;;
;; Redoing takes you back down the undo tree, as usual (as long as you haven't
;; changed the active region after undoing-in-region, it doesn't matter if it
;; is still active):
;;
;;       o
;;       |
;;       |
;;       |
;;       o_
;;       | \
;;       |  o
;;       |  |
;;       o  |
;;       |  |
;;       |  o  (redo)
;;       |  |
;;       o  x  (redo)
;;
;;
;; What about redo-in-region? Obviously, redo-in-region only makes sense if
;; you have already undone some changes, so that there are some changes to
;; redo! Redoing-in-region splits off a new branch of the undo history below
;; your current location in the undo tree. This time, the new branch consists
;; of a first redo step that redoes some of the redo changes that affect the
;; current region, followed by *all* the remaining redo changes.
;;
;;      Previous undo history                Redo-in-region
;;
;;               o                                o
;;               |                                |
;;               |                                |
;;               |                                |
;;               x                                o_
;;               |                                | \
;;               |                                |  x  (redo-in-region)
;;               |                                |  |
;;               o                                o  |
;;               |                                |  |
;;               |                                |  |
;;               |                                |  |
;;               o                                o  o
;;
;; As long as you don't change the active region after redoing-in-region,
;; continuing to redo-in-region extends the new branch, pulling more redo
;; changes into a redo step immediately below your current location in the
;; undo tree.
;;
;;      First redo-in-region                 Second redo-in-region
;;
;;               o                                 o
;;               |                                 |
;;               |                                 |
;;               |                                 |
;;               o_                                o_
;;               | \                               | \
;;               |  x                              |  o
;;               |  |                              |  |
;;               o  |                              o  |
;;               |  |                              |  |
;;               |  |                              |  x  (redo-in-region)
;;               |  |                              |  |
;;               o  o                              o  o
;;
;; Note that undo-in-region and redo-in-region only ever add new changes to
;; the undo tree, they *never* modify existing undo history. So you can always
;; return to previous buffer states by switching to a previous branch of the
;; tree.

;;; Code:

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Compatibility hacks for older Emacsen

;;; Please note that older versions of Emacs will not be tested by @lawlist.
;;; Users are encouraged to upgrade to a current version of Emacs.

;; `characterp' isn't defined in Emacs versions < 23
(unless (fboundp 'characterp)
  (defalias 'characterp 'char-valid-p))

;; `region-active-p' isn't defined in Emacs versions < 23
(unless (fboundp 'region-active-p)
  (defun region-active-p () (and transient-mark-mode mark-active)))

;; `registerv' defstruct isn't defined in Emacs versions < 24
(unless (fboundp 'registerv-make)
  (defmacro registerv-make (data &rest _dummy) data))

(unless (fboundp 'registerv-data)
  (defmacro registerv-data (data) data))

;; `diff-no-select' and `diff-file-local-copy' aren't defined in Emacs
;; versions < 24 (copied and adapted from Emacs 24)
(unless (fboundp 'diff-no-select)
  (defun diff-no-select (old new &optional switches no-async buf)
    "Noninteractive helper for creating and reverting diff buffers."
    (unless (bufferp new) (setq new (expand-file-name new)))
    (unless (bufferp old) (setq old (expand-file-name old)))
    (or switches (setq switches diff-switches)) ; If not specified, use default.
    (unless (listp switches) (setq switches (list switches)))
    (or buf (setq buf (get-buffer-create "*Diff*")))
    (let* ((old-alt (diff-file-local-copy old))
           (new-alt (diff-file-local-copy new))
           (command
            (mapconcat 'identity
                 `(,diff-command
             ;; Use explicitly specified switches
             ,@switches
             ,@(mapcar #'shell-quote-argument
                 (nconc
                  (when (or old-alt new-alt)
                    (list "-L" (if (stringp old)
                       old (prin1-to-string old))
                    "-L" (if (stringp new)
                       new (prin1-to-string new))))
                  (list (or old-alt old)
                  (or new-alt new)))))
                 " "))
           (thisdir default-directory))
      (with-current-buffer buf
        (setq buffer-read-only t)
        (buffer-disable-undo (current-buffer))
        (let ((inhibit-read-only t))
          (erase-buffer))
        (buffer-enable-undo (current-buffer))
        (diff-mode)
        (set (make-local-variable 'revert-buffer-function)
             (lambda (_ignore-auto _noconfirm)
               (diff-no-select old new switches no-async (current-buffer))))
        (setq default-directory thisdir)
        (let ((inhibit-read-only t))
          (insert command "\n"))
        (if (and (not no-async) (fboundp 'start-process))
            (let ((proc (start-process "Diff" buf shell-file-name shell-command-switch command)))
              (set-process-filter proc 'diff-process-filter)
              (set-process-sentinel
                proc
                (lambda (proc _msg)
                  (with-current-buffer (process-buffer proc)
                    (diff-sentinel (process-exit-status proc))
                    (if old-alt (delete-file old-alt))
                    (if new-alt (delete-file new-alt))))))
          ;; Async processes aren't available.
          (let ((inhibit-read-only t))
            (diff-sentinel
              (call-process shell-file-name nil buf nil shell-command-switch command))
            (if old-alt (delete-file old-alt))
            (if new-alt (delete-file new-alt)))))
      buf)))

(unless (fboundp 'diff-file-local-copy)
  (defun diff-file-local-copy (file-or-buf)
    (if (bufferp file-or-buf)
      (with-current-buffer file-or-buf
        (let ((tempfile (make-temp-file "buffer-content-")))
          (write-region nil nil tempfile nil 'nomessage)
          tempfile))
      (file-local-copy file-or-buf))))

;; `user-error' isn't defined in Emacs < 24.3
(unless (fboundp 'user-error)
  (defalias 'user-error 'error)
  ;; prevent debugger being called on user errors
  (add-to-list 'debug-ignored-errors "^No further undo information")
  (add-to-list 'debug-ignored-errors "^No further redo information")
  (add-to-list 'debug-ignored-errors "^No further redo information for region"))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Global variables and customization options

(defvar undo-tree-list nil
  "Tree of undo entries in current buffer.")
(put 'undo-tree-list 'permanent-local t)
(make-variable-buffer-local 'undo-tree-list)

(defgroup undo-tree nil
  "Tree undo/redo."
  :group 'undo)

(defcustom undo-tree-mode-lighter " UT"
  "Lighter displayed in mode line
when `undo-tree-mode' is enabled."
  :group 'undo-tree
  :type 'string)

(defcustom undo-tree--undo-limit 4000000
  "Limit used by `undo-tree-discard-history--one-of-two'"
  :group 'undo-tree
  :type 'integer)

(defcustom undo-tree--undo-strong-limit 6000000
  "Limit used by `undo-tree-discard-history--one-of-two'"
  :group 'undo-tree
  :type 'integer)

(defcustom undo-tree--undo-outer-limit 36000000
  "Limit used by `undo-tree-discard-history--one-of-two'"
  :group 'undo-tree
  :type 'integer)

(defvar undo-tree-linear-history nil
"Visualize the linear history with timestamps.")
(make-variable-buffer-local 'undo-tree-linear-history)

;;; ERROR:  `Unrecognized entry in undo list undo-tree-canary`
;;; https://debbugs.gnu.org/cgi/bugreport.cgi?bug=16377
;;; https://debbugs.gnu.org/cgi/bugreport.cgi?bug=16523
(defcustom undo-tree-enable-undo-in-region nil
  "When non-nil, enable undo-in-region.
When undo-in-region is enabled, undoing or redoing when the
region is active (in `transient-mark-mode') or with a prefix
argument (not in `transient-mark-mode') only undoes changes
within the current region."
  :group 'undo-tree
  :type 'boolean)

(defcustom undo-tree-visual-relative-timestamps nil
  "When non-nil, display times relative to current time
when displaying time stamps in visualizer.
Otherwise, display absolute times."
  :group 'undo-tree
  :type 'boolean)

(defcustom undo-tree-visual-timestamps nil
  "When non-nil, display time-stamps by default
in undo-tree visualizer.
\\<undo-tree-visual-mode-map>You can always toggle time-stamps on and off \
using \\[undo-tree-visual-toggle-timestamps], regardless of the
setting of this variable."
  :group 'undo-tree
  :type 'boolean)
(make-variable-buffer-local 'undo-tree-visual-timestamps)

(defcustom undo-tree-visual-diff nil
  "When non-nil, display diff by default in undo-tree visualizer.
\\<undo-tree-visual-mode-map>You can always toggle the diff display \
using \\[undo-tree-visual-toggle-diff], regardless of the
setting of this variable."
  :group 'undo-tree
  :type 'boolean)
(make-variable-buffer-local 'undo-tree-visual-diff)

(defcustom undo-tree-visual-lazy-drawing nil
  "When non-nil, use lazy undo-tree drawing in visualizer.
-  Setting this to a number causes the visualizer to switch to lazy
drawing when the number of nodes in the tree is larger than this
value.
-  Lazy drawing means that only the visible portion of the tree will
be drawn initially, and the tree will be extended later as
needed. For the most part, the only visible effect of this is to
significantly speed up displaying the visualizer for very large
trees.
-  There is one potential negative effect of lazy drawing. Other
branches of the tree will only be drawn once the node from which
they branch off becomes visible. So it can happen that certain
portions of the tree that would be shown with lazy drawing
disabled, will not be drawn immediately when it is
enabled. However, this effect is quite rare in practice."
  :group 'undo-tree
  :type '(choice (const :tag "never" nil)
     (const :tag "always" t)
     (integer :tag "> size")))

;; persistent storage variables

(defcustom undo-tree-history-autosave nil
  "When non-nil, `undo-tree-mode' will save undo history to file
when a buffer is saved to file.
-  It will automatically load undo history when a buffer is loaded
from file, if an undo save file exists.
-  By default, undo-tree history is saved to a file called
\".<buffer-file-name>.~undo-tree~\" in the same directory as the
file itself. To save under a different directory, customize
`undo-tree-history-alist' (see the documentation for
that variable for details).
-  WARNING! `undo-tree-history-autosave' will not work properly in
Emacs versions prior to 24.3, so it cannot be enabled via
the customization interface in versions earlier than that one. To
ignore this warning and enable it regardless, set
`undo-tree-history-autosave' to a non-nil value outside of
customize."
  :group 'undo-tree
  :type (if (version-list-< (version-to-list emacs-version) '(24 3))
      '(choice (const :tag "<disabled>" nil))
    'boolean))

(defcustom undo-tree-history-alist nil
"This variable is used when `undo-tree-history-storage' is 'classic.
Alist of filename patterns and undo history directory names.
Each element looks like (REGEXP . DIRECTORY).  Undo history for
files with names matching REGEXP will be saved in DIRECTORY.
DIRECTORY may be relative or absolute.  If it is absolute, so
that all matching files are backed up into the same directory,
the file names in this directory will be the full name of the
file backed up with all directory separators changed to `!' to
prevent clashes.  This will not work correctly if your filesystem
truncates the resulting name.
-  For the common case of all backups going into one directory, the
alist should contain a single element pairing \".\" with the
appropriate directory name.
-  If this variable is nil, or it fails to match a filename, the
backup is made in the original file's directory.
-  On MS-DOS filesystems without long names this variable is always
ignored."
  :group 'undo-tree
  :type '(repeat (cons (regexp :tag "Regexp matching filename")
           (directory :tag "Undo history directory name"))))

;;; Code is copied from `image-dired.el'.
(defcustom undo-tree-history-directory (concat user-emacs-directory ".0.undo-tree/")
  "Directory where undo-tree history files are stored
when `undo-tree-history-storage' is set to 'central.
We need the forward trailing slash."
  :type 'string
  :group 'undo-tree)

;;; Code is copied from `image-dired.el'.
(defcustom undo-tree-history-storage 'classic
"How to store undo-tree history files.  The available options are symbols:
(1) 'classic -- control the location with `undo-tree-history-alist'
(2) 'home -- put everything in a folder in the HOME directory.
(3) 'central -- one central location set by `undo-tree-history-directory'
(4) 'local -- create sub-directories in each working directory."
  :type '(choice :tag "How to store undo-tree history files"
                 (const :tag "Classic Method" classic)
                 (const :tag "Generic Managing Standard" home)
                 (const :tag "Use undo-tree-history-directory" central)
                 (const :tag "Per-directory" local))
  :group 'undo-tree)

;; exclusions:  major-modes; buffer-names; absolute file names

(defcustom undo-tree-exclude-modes '(term-mode)
"List of major-modes to be excluded when turning on `undo-tree-mode';
and when saving a buffer."
  :group 'undo-tree
  :type '(repeat symbol))

(defvar undo-tree-exclude-buffers '("\\*temp\\*" "^\\*messages\\*$" "^\\*grep\\*$" "^\\*capture\\*$")
"List of regexp matching buffer names to be excluded when turning on `undo-tree-mode';
and when saving a buffer.")

(defvar undo-tree-exclude-files '()
"A list of absolute file names to be excluded when turning on `undo-tree-mode';
and when saving a buffer.")

;; visualizer buffer names

(defconst undo-tree-visual-buffer-name "*undo-tree*")

(defconst undo-tree-diff-buffer-name "*undo-tree Diff*")

;; visualizer internal variables

(defvar undo-tree-visual-parent-buffer nil
  "Parent buffer in visualizer.")
(put 'undo-tree-visual-parent-buffer 'permanent-local t)
(make-variable-buffer-local 'undo-tree-visual-parent-buffer)

(defvar undo-tree-visual-parent-mtime nil
"Stores modification time of parent buffer's file, if any.")
(put 'undo-tree-visual-parent-mtime 'permanent-local t)
(make-variable-buffer-local 'undo-tree-visual-parent-mtime)

(defvar undo-tree-visual-spacing nil
"Stores current horizontal spacing needed for drawing undo-tree.")
(put 'undo-tree-visual-spacing 'permanent-local t)
(make-variable-buffer-local 'undo-tree-visual-spacing)

(defvar undo-tree-visual-initial-node nil
"Holds node that was current when visualizer was invoked.")
(put 'undo-tree-visual-initial-node 'permanent-local t)
(make-variable-buffer-local 'undo-tree-visual-initial-node)

(defvar undo-tree-visual-selected-node nil
"Holds currently selected node in visualizer selection mode.")
(put 'undo-tree-visual-selected-node 'permanent-local t)
(make-variable-buffer-local 'undo-tree-visual-selected)

(defvar undo-tree-visual-needs-extending-down nil
"Used to store nodes at edge of currently drawn portion of tree.")
(put 'undo-tree-visual-needs-extending-down 'permanent-local t)
(make-variable-buffer-local 'undo-tree-visual-needs-extending-down)

(defvar undo-tree-visual-needs-extending-up nil)
(put 'undo-tree-visual-needs-extending-up 'permanent-local t)
(make-variable-buffer-local 'undo-tree-visual-needs-extending-up)

(defvar undo-tree-inhibit-kill-visual nil
"Dynamically bound to t when undoing from visualizer, to inhibit the
`undo-tree-kill-visual' hook function in parent buffer.")

(defvar undo-tree-insert-face nil
"Can be let-bound to a face name, which is used in drawing functions.")

(defvar *undo-tree-id-counter* 0
"Variable used by the function `undo-tree-generate-id'.")
(make-variable-buffer-local '*undo-tree-id-counter*)

;;; dynamically bound -- used by `undo-elt-in-region'.
(defvar undo-tree-adjusted-markers)

;;; dynamically bound -- used by `undo-tree-label-nodes--two-of-two'.
(defvar undo-tree-branch-count)
(defvar undo-tree-branch-point-count)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Faces

(defface undo-tree-mouseover-face
  '((t (:foreground "brown")))
"Face for `undo-tree-mouseover-face'."
  :group 'undo-tree)

(defface undo-tree-linear--node-selected-face
  '((t (:foreground "OrangeRed")))
"Face for `undo-tree-linear--node-selected-face'."
  :group 'undo-tree)

(defface undo-tree-linear--node-unselected-face
  '((t (:foreground "#3c3c3c")))
"Face for `undo-tree-linear--node-unselected-face'."
  :group 'undo-tree)

(defface undo-tree-linear--br/pt-selected-active-face
  '((t (:foreground "OrangeRed")))
"Face for `undo-tree-linear--br/pt-selected-active-face'."
  :group 'undo-tree)

(defface undo-tree-linear--br/pt-selected-inactive-face
  '((t (:background "green" :foreground "black")))
"Face for `undo-tree-linear--br/pt-selected-inactive-face'.
This potential feature is presently deactivated."
  :group 'undo-tree)

(defface undo-tree-linear--br/pt-unselected-active-face
  '((t (:foreground "blue")))
"Face for `undo-tree-linear--br/pt-unselected-active-face'."
  :group 'undo-tree)

(defface undo-tree-linear--br/pt-unselected-inactive-face
  '((t (:foreground "#3c3c3c")))
"Face for `undo-tree-linear--br/pt-unselected-inactive-face'."
  :group 'undo-tree)

(defface undo-tree-visual-lazy-drawing-face
  '((t (:foreground "RoyalBlue")))
"Face used to draw undo-tree in visualizer."
  :group 'undo-tree)

(defface undo-tree-visual-default-face
  '((((class color) (background light))
     :foreground "blue")
    (((class color) (background dark))
     :foreground "Dark Green")
    (t
     :foreground "gray95"))
"Face used to draw undo-tree in visualizer."
  :group 'undo-tree)

(defface undo-tree-visual-current-face
  '((t (:foreground "red")))
"Face used to highlight current undo-tree node in visualizer."
  :group 'undo-tree)

(defface undo-tree-visual-active-branch-face
  '((((class color) (background light))
     :foreground "magenta")
    (((class color) (background dark))
     :foreground "magenta")
    (t
     :foreground "gray"))
"Face used to highlight active undo-tree branch in visualizer."
  :group 'undo-tree)

(defface undo-tree-visual-register-face
  '((((class color) (background light))
     :foreground "yellow")
    (((class color) (background dark))
     :foreground "yellow")
    (t
     :foreground "gray"))
"Face used to highlight undo-tree nodes saved to a register
in visualizer."
  :group 'undo-tree)

(defface undo-tree-visual-unmodified-face
  '((((class color) (background light))
     :foreground "cyan")
    (((class color) (background dark))
     :foreground "cyan")
    (t
     :foreground "gray"))
"Face used to highlight nodes corresponding to unmodified buffers
in visualizer."
  :group 'undo-tree)

(defface undo-tree-visual-mode-line-face
  '((t (:foreground "firebrick")))
"Face used to indicate the undo-tree-count in visualizer."
  :group 'undo-tree)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Default keymaps

(defvar undo-tree-mouse-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-2] 'undo-tree-follow-link)
    (define-key map [return] 'undo-tree-follow-link)
    (define-key map [follow-link] 'mouse-face)
      map)
"Keymap for mouse when in the visualizer buffer.")

(defun undo-tree-follow-link (event)
"Follow the link."
(interactive (list last-nonmenu-event))
  (run-hooks 'mouse-leave-buffer-hook)
  (with-current-buffer (window-buffer (posn-window (event-start event)))
    (let ((pt (posn-point (event-start event))))
      (undo-tree-visual-set pt))))

(defvar undo-tree-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [?\s-u] 'undo-tree-linear-undo)
    (define-key map [?\s-r] 'undo-tree-linear-redo)
    (define-key map [?\s-z] 'undo-tree-linear-undo)
    (define-key map [?\s-Z] 'undo-tree-linear-redo)
    ;; remap `undo' and `undo-only' to `undo-tree-classic-undo'
    (define-key map [remap undo] 'undo-tree-classic-undo)
    (define-key map [remap undo-only] 'undo-tree-classic-undo)
    ;; bind standard undo bindings (since these match redo counterparts)
    (define-key map (kbd "C-/") 'undo-tree-classic-undo)
    (define-key map "\C-_" 'undo-tree-classic-undo)
    ;; redo doesn't exist normally, so define our own keybindings
    (define-key map (kbd "C-?") 'undo-tree-classic-redo)
    (define-key map (kbd "M-_") 'undo-tree-classic-redo)
    ;; just in case something has defined `redo'...
    (define-key map [remap redo] 'undo-tree-classic-redo)
    ;; we use "C-x u" for the undo-tree visualizer
    (define-key map (kbd "\C-x u") 'undo-tree-visual)
    ;; bind register commands
    (define-key map (kbd "C-x r u") 'undo-tree-save-state-to-register)
    (define-key map (kbd "C-x r U") 'undo-tree-restore-state-from-register)
    ;; set keymap
    map)
"Keymap used in undo-tree-mode.")

(defvar undo-tree-visual-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "u" 'undo-tree-visual-linear-undo)
    (define-key map "r" 'undo-tree-visual-linear-redo)
    (define-key map "z" 'undo-tree-visual-linear-undo)
    (define-key map "Z" 'undo-tree-visual-linear-redo)
    ;; vertical motion keys undo/redo
    (define-key map [remap previous-line] 'undo-tree-visual-classic-undo)
    (define-key map [remap next-line] 'undo-tree-visual-classic-redo)
    (define-key map [up] 'undo-tree-visual-classic-undo)
    (define-key map [menu-bar undo-tree]
      (cons "Undo Tree" (make-sparse-keymap "Undo Tree")))
    (define-key map "p" 'undo-tree-visual-classic-undo)
    (bindings--define-key map [menu-bar undo-tree undo-tree-visual-classic-undo]
      '(menu-item "undo-tree-visual-classic-undo" undo-tree-visual-classic-undo
        :help "My help string:  undo-tree-visual-classic-undo"))
    (define-key map "\C-p" 'undo-tree-visual-classic-undo)
    (define-key map [down] 'undo-tree-visual-classic-redo)
    (define-key map "n" 'undo-tree-visual-classic-redo)
    (bindings--define-key map [menu-bar undo-tree undo-tree-visual-classic-redo]
      '(menu-item "undo-tree-visual-classic-redo" undo-tree-visual-classic-redo
        :help "My help string:  undo-tree-visual-classic-redo"))
    (define-key map "\C-n" 'undo-tree-visual-classic-redo)
    ;; horizontal motion keys switch branch
    (define-key map [remap forward-char] 'undo-tree-visual-switch-branch-right)
    (define-key map [remap backward-char] 'undo-tree-visual-switch-branch-left)
    (define-key map [right] 'undo-tree-visual-switch-branch-right)
    (define-key map "f" 'undo-tree-visual-switch-branch-right)
    (bindings--define-key map [menu-bar undo-tree undo-tree-visual-switch-branch-right]
      '(menu-item "undo-tree-visual-switch-branch-right" undo-tree-visual-switch-branch-right
        :help "My help string:  undo-tree-visual-switch-branch-right"))
    (define-key map "\C-f" 'undo-tree-visual-switch-branch-right)
    (define-key map [left] 'undo-tree-visual-switch-branch-left)
    (define-key map "b" 'undo-tree-visual-switch-branch-left)
    (bindings--define-key map [menu-bar undo-tree undo-tree-visual-switch-branch-left]
      '(menu-item "undo-tree-visual-switch-branch-left" undo-tree-visual-switch-branch-left
        :help "My help string:  undo-tree-visual-switch-branch-left"))
    (define-key map "\C-b" 'undo-tree-visual-switch-branch-left)
    ;; paragraph motion keys undo/redo to significant points in tree
    (define-key map [remap backward-paragraph] 'undo-tree-visual-undo-to-x)
    (define-key map [remap forward-paragraph] 'undo-tree-visual-redo-to-x)
    (define-key map "\M-{" 'undo-tree-visual-undo-to-x)
    (define-key map "\M-}" 'undo-tree-visual-redo-to-x)
    (define-key map [C-up] 'undo-tree-visual-undo-to-x)
    (bindings--define-key map [menu-bar undo-tree undo-tree-visual-undo-to-x]
      '(menu-item "undo-tree-visual-undo-to-x" undo-tree-visual-undo-to-x
        :help "My help string:  undo-tree-visual-undo-to-x"))
    (define-key map [C-down] 'undo-tree-visual-redo-to-x)
    (bindings--define-key map [menu-bar undo-tree undo-tree-visual-redo-to-x]
      '(menu-item "undo-tree-visual-redo-to-x" undo-tree-visual-redo-to-x
        :help "My help string:  undo-tree-visual-redo-to-x"))
    ;; mouse sets buffer state to node at click
    (define-key map [mouse-1] 'undo-tree-visual-mouse-set)
    ;; toggle timestamps
    (define-key map "t" 'undo-tree-visual-toggle-timestamps)
    (bindings--define-key map [menu-bar undo-tree undo-tree-visual-toggle-timestamps]
      '(menu-item "undo-tree-visual-toggle-timestamps" undo-tree-visual-toggle-timestamps
        :help "My help string:  undo-tree-visual-toggle-timestamps"))
    ;; toggle diff
    (define-key map "d" 'undo-tree-visual-toggle-diff)
    (bindings--define-key map [menu-bar undo-tree undo-tree-visual-toggle-diff]
      '(menu-item "undo-tree-visual-toggle-diff" undo-tree-visual-toggle-diff
        :help "My help string:  undo-tree-visual-toggle-diff"))
    ;; toggle selection mode
    (define-key map "s" 'undo-tree-visual-selection-mode)
    (bindings--define-key map [menu-bar undo-tree undo-tree-visual-selection-mode]
      '(menu-item "undo-tree-visual-selection-mode" undo-tree-visual-selection-mode
        :help "My help string:  undo-tree-visual-selection-mode"))
    ;; horizontal scrolling may be needed if the tree is very wide
    (define-key map "," 'undo-tree-visual-scroll-left)
    (define-key map "." 'undo-tree-visual-scroll-right)
    (define-key map "<" 'undo-tree-visual-scroll-left)
    (bindings--define-key map [menu-bar undo-tree undo-tree-visual-scroll-left]
      '(menu-item "undo-tree-visual-scroll-left" undo-tree-visual-scroll-left
        :help "My help string:  undo-tree-visual-scroll-left"))
    (define-key map ">" 'undo-tree-visual-scroll-right)
    (bindings--define-key map [menu-bar undo-tree undo-tree-visual-scroll-right]
      '(menu-item "undo-tree-visual-scroll-right" undo-tree-visual-scroll-right
        :help "My help string:  undo-tree-visual-scroll-right"))
    ;; vertical scrolling may be needed if the tree is very tall
    (define-key map [next] 'undo-tree-visual-scroll-up)
    (define-key map [prior] 'undo-tree-visual-scroll-down)
    ;; quit/abort visualizer
    (define-key map "q" 'undo-tree-visual-quit)
    (bindings--define-key map [menu-bar undo-tree undo-tree-visual-quit]
      '(menu-item "undo-tree-visual-quit" undo-tree-visual-quit
        :help "My help string:  undo-tree-visual-quit"))
    (define-key map "\C-q" 'undo-tree-visual-abort)
    (bindings--define-key map [menu-bar undo-tree undo-tree-visual-abort]
      '(menu-item "undo-tree-visual-abort" undo-tree-visual-abort
        :help "My help string:  undo-tree-visual-abort"))
    ;; set keymap
    map)
"Keymap used in undo-tree visualizer.")

(defvar undo-tree-visual-selection-mode-map
  (let ((map (make-sparse-keymap)))
    ;; vertical motion keys move up and down tree
    (define-key map [remap previous-line] 'undo-tree-visual-select-previous)
    (define-key map [remap next-line] 'undo-tree-visual-select-next)
    (define-key map [up] 'undo-tree-visual-select-previous)
    (define-key map "p" 'undo-tree-visual-select-previous)
    (define-key map "\C-p" 'undo-tree-visual-select-previous)
    (define-key map [down] 'undo-tree-visual-select-next)
    (define-key map "n" 'undo-tree-visual-select-next)
    (define-key map "\C-n" 'undo-tree-visual-select-next)
    ;; vertical scroll keys move up and down quickly
    (define-key map [next] (lambda () (interactive) (undo-tree-visual-select-next 10)))
    (define-key map [prior] (lambda () (interactive) (undo-tree-visual-select-previous 10)))
    ;; horizontal motion keys move to left and right siblings
    (define-key map [remap forward-char] 'undo-tree-visual-select-right)
    (define-key map [remap backward-char] 'undo-tree-visual-select-left)
    (define-key map [right] 'undo-tree-visual-select-right)
    (define-key map "f" 'undo-tree-visual-select-right)
    (define-key map "\C-f" 'undo-tree-visual-select-right)
    (define-key map [left] 'undo-tree-visual-select-left)
    (define-key map "b" 'undo-tree-visual-select-left)
    (define-key map "\C-b" 'undo-tree-visual-select-left)
    ;; horizontal scroll keys move left or right quickly
    (define-key map "," (lambda () (interactive) (undo-tree-visual-select-left 10)))
    (define-key map "." (lambda () (interactive) (undo-tree-visual-select-right 10)))
    (define-key map "<" (lambda () (interactive) (undo-tree-visual-select-left 10)))
    (define-key map ">" (lambda () (interactive) (undo-tree-visual-select-right 10)))
    ;; <enter> sets buffer state to node at point
    (define-key map "\r" 'undo-tree-visual-set)
    (define-key map [return] 'undo-tree-visual-set)
    ;; mouse selects node at click
    (define-key map [mouse-1] 'undo-tree-visual-mouse-select)
    ;; toggle diff
    (define-key map "d" 'undo-tree-visual-selection-toggle-diff)
    ;; set keymap
    map)
"Keymap used in undo-tree visualizer selection mode.")

(defvar undo-tree-old-undo-menu-item nil)

(defun undo-tree-update-menu-bar ()
"Update `undo-tree-mode' Edit menu items."
  (if undo-tree-mode
    (progn
      ;; save old undo menu item, and install undo/redo menu items
      (setq undo-tree-old-undo-menu-item
            (cdr (assq 'undo (lookup-key global-map [menu-bar edit]))))
      (define-key (lookup-key global-map [menu-bar edit])
        [undo] '(menu-item "Undo" undo-tree-classic-undo
               :enable (and undo-tree-mode
                (not buffer-read-only)
                (not (eq t buffer-undo-list))
                (not (eq nil undo-tree-list))
                (undo-tree-node-previous (undo-tree-current undo-tree-list)))
               :help "Undo last operation"))
      (define-key-after (lookup-key global-map [menu-bar edit])
        [redo] '(menu-item "Redo" undo-tree-classic-redo
               :enable (and undo-tree-mode
                (not buffer-read-only)
                (not (eq t buffer-undo-list))
                (not (eq nil undo-tree-list))
                (undo-tree-node-next (undo-tree-current undo-tree-list)))
               :help "Redo last operation")
        'undo))
    ;; uninstall undo/redo menu items
    (define-key (lookup-key global-map [menu-bar edit]) [undo] undo-tree-old-undo-menu-item)
    (define-key (lookup-key global-map [menu-bar edit]) [redo] nil)))

(add-hook 'menu-bar-update-hook 'undo-tree-update-menu-bar)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun undo-tree--primitive-undo (n list)
"Undo N records from the front of the list LIST.
Return what remains of the list."
  (let ((arg n)
        ;; In a writable buffer, enable undoing read-only text that is
        ;; so because of text properties.
        (inhibit-read-only t)
        ;; Don't let `intangible' properties interfere with undo.
        (inhibit-point-motion-hooks t)
        ;; We use oldlist only to check for EQ.  ++kfs
        (oldlist buffer-undo-list)
        (did-apply nil)
        (next nil)
        (window-of-current-buffer (get-buffer-window (current-buffer)))
        (selected-window (selected-window)))
    (while (> arg 0)
      (while (setq next (pop list))     ;Exit inner loop at undo boundary.
        ;; Handle an integer by setting point to that value.
        (pcase next
          ((pred integerp)
            (goto-char next)
              (unless (eq window-of-current-buffer selected-window)
                (set-window-point window-of-current-buffer next)))
          ;; Element (t . TIME) records previous modtime.
          ;; Preserve any flag of NONEXISTENT_MODTIME_NSECS or
          ;; UNKNOWN_MODTIME_NSECS.
          (`(t . ,time)
           ;; If this records an obsolete save
           ;; (not matching the actual disk file)
           ;; then don't mark unmodified.
            (when (or (equal time (visited-file-modtime))
                      (and (consp time)
                           (equal (list (car time) (cdr time)) (visited-file-modtime))))
              (when (fboundp 'unlock-buffer)
                (unlock-buffer))
              (set-buffer-modified-p nil)))
          ;; Element (nil PROP VAL BEG . END) is property change.
          (`(nil . ,(or `(,prop ,val ,beg . ,end) pcase--dontcare))
            (when (or (> (point-min) beg) (< (point-max) end))
              (let ((debug-on-quit nil)
                    (msg (concat
                           "undo-tree--primitive-undo (1 of 4):"
                           "  "
                           "Changes to be undone are outside visible portion of buffer.")))
                (signal 'quit `(,msg))))
           (put-text-property beg end prop val))
          ;; Element (BEG . END) means range was inserted.
          (`(,(and beg (pred integerp)) . ,(and end (pred integerp)))
           ;; (and `(,beg . ,end) `(,(pred integerp) . ,(pred integerp)))
           ;; Ideally: `(,(pred integerp beg) . ,(pred integerp end))
            (when (or (> (point-min) beg) (< (point-max) end))
              (let ((debug-on-quit nil)
                    (msg (concat
                           "undo-tree--primitive-undo (2 of 4):"
                           "  "
                           "Changes to be undone are outside visible portion of buffer.")))
                (signal 'quit `(,msg))))
           ;; Set point first thing, so that undoing this undo
           ;; does not send point back to where it is now.
           (goto-char beg)
           (delete-region beg end)
           (unless (eq window-of-current-buffer selected-window)
             (set-window-point window-of-current-buffer beg)))
          ;; Element (apply FUN . ARGS) means call FUN to undo.
          (`(apply . ,fun-args)
           (let ((currbuff (current-buffer)))
             (if (integerp (car fun-args))
                 ;; Long format: (apply DELTA START END FUN . ARGS).
                 (pcase-let* ((`(,delta ,start ,end ,fun . ,args) fun-args)
                              (start-mark (copy-marker start nil))
                              (end-mark (copy-marker end t)))
                    (when (or (> (point-min) start) (< (point-max) end))
              (let ((debug-on-quit nil)
                    (msg (concat
                           "undo-tree--primitive-undo (3 of 4):"
                           "  "
                           "Changes to be undone are outside visible portion of buffer.")))
                (signal 'quit `(,msg))))
                   (apply fun args) ;; Use `save-current-buffer'?
                   ;; Check that the function did what the entry
                   ;; said it would do.
                   (unless (and (= start start-mark)
                                (= (+ delta end) end-mark))
                     (error "Changes to be undone by function different than announced"))
                   (set-marker start-mark nil)
                   (set-marker end-mark nil))
               (apply fun-args))
             (unless (eq currbuff (current-buffer))
               (error "Undo function switched buffer"))
             (setq did-apply t)))
          ;; Element (STRING . POS) means STRING was deleted.
          (`(,(and string (pred stringp)) . ,(and pos (pred integerp)))
           (when (let ((apos (abs pos)))
                    (or (< apos (point-min)) (> apos (point-max))))
              (let ((debug-on-quit nil)
                    (msg (concat
                           "undo-tree--primitive-undo (4 of 4):"
                           "  "
                           "Changes to be undone are outside visible portion of buffer.")))
                (signal 'quit `(,msg))))
           (let (valid-marker-adjustments)
             ;; Check that marker adjustments which were recorded
             ;; with the (STRING . POS) record are still valid, ie
             ;; the markers haven't moved.  We check their validity
             ;; before reinserting the string so as we don't need to
             ;; mind marker insertion-type.
             (while (and (markerp (car-safe (car list)))
                         (integerp (cdr-safe (car list))))
               (let* ((marker-adj (pop list))
                      (m (car marker-adj)))
                 (and (eq (marker-buffer m) (current-buffer))
                      (= pos m)
                      (push marker-adj valid-marker-adjustments))))
             ;; Insert string and adjust point
             (if (< pos 0)
                 (progn
                   (goto-char (- pos))
                   (insert string))
               (goto-char pos)
               (insert string)
               (goto-char pos))
             (unless (eq window-of-current-buffer selected-window)
               (set-window-point window-of-current-buffer pos))
             ;; Adjust the valid marker adjustments
             (dolist (adj valid-marker-adjustments)
               ;; Insert might have invalidated some of the markers
               ;; via modification hooks.  Update only the currently
               ;; valid ones (bug#25599).
               (if (marker-buffer (car adj))
                   (set-marker (car adj)
                               (- (car adj) (cdr adj)))))))
          ;; (MARKER . OFFSET) means a marker MARKER was adjusted by OFFSET.
          (`(,(and marker (pred markerp)) . ,(and offset (pred integerp)))
            (let ((msg
                    (concat
                      "undo-tree--primitive-undo:  "
                      (format "Encountered %S entry in undo list with no matching (TEXT . POS) entry"
                              next))))
              (message msg))
           ;; Even though these elements are not expected in the undo
           ;; list, adjust them to be conservative for the 24.4
           ;; release.  (Bug#16818)
           (when (marker-buffer marker)
             (set-marker marker
                         (- marker offset)
                         (marker-buffer marker))))
          (_
            (if (eq next 'undo-tree-canary)
              (message "undo-tree--primitive-undo:  catch-all found `%s'." next)
              (error "Unrecognized entry in undo list %S" next)))))
      (setq arg (1- arg)))
    ;; Make sure an apply entry produces at least one undo entry,
    ;; so the test in `undo' for continuing an undo series
    ;; will work right.
    (if (and did-apply
             (eq oldlist buffer-undo-list))
        (setq buffer-undo-list
              (cons (list 'apply 'cdr nil) buffer-undo-list))))
  list)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Undo-tree data structure

;;; Written by Drew Adams (@Drew):  https://emacs.stackexchange.com/a/22635/2287
(defun drew-adams--true-listp (object)
"Return non-`nil' if OBJECT is a true list -- i.e., not a dotted cons-cell."
  (and (listp object)  (null (cdr (last object)))))

;; https://github.com/kentaro/auto-save-buffers-enhanced
;; function modified by @sds on stackoverflow:  http://stackoverflow.com/a/20343715/2112489
(defun undo-tree-regexp-match-p (regexps string)
  (and string
       (catch 'matched
         (let ((inhibit-changing-match-data t)) ; small optimization
           (dolist (regexp regexps)
             (when (string-match regexp string)
               (throw 'matched t)))))))

;;; Use `symbol-function' to inspect the value.
;;;
;;; `cl-struct-undo-tree':  nth 0 index of the `undo-tree-list' array.
;;;                          (aref undo-tree-list 0)
;;;
;;; `undo-tree-root':  nth 1 index of the `undo-tree-list' array.
;;;                    (aref undo-tree-list 1)
;;;                    (undo-tree-root undo-tree-list)
;;;
;;; `undo-tree-current':  nth 2 index of the `undo-tree-list' array.
;;;                       (aref undo-tree-list 2)
;;;                       (undo-tree-current undo-tree-list)
;;;
;;; `undo-tree-size':  nth 3 index of the `undo-tree-list' array.
;;;                   (aref undo-tree-list 3)
;;;                   (undo-tree-size undo-tree-list)
;;;
;;; `undo-tree-count':  nth 4 index of the `undo-tree-list' array.
;;;                     (aref undo-tree-list 4)
;;;                     (undo-tree-count undo-tree-list)
;;;
;;; `undo-tree-object-pool':  nth 5 index of the `undo-tree-list' array.
;;;                           (aref undo-tree-list 5)
;;;                           (undo-tree-object-pool undo-tree-list)
;;;
;;; `undo-tree-previous':  nth 6 index of the `undo-tree-list' array.
;;;                       (aref undo-tree-list 6)
;;;                       (undo-tree-previous undo-tree-list)
;;;
(cl-defstruct
  (undo-tree
    :named
    (:constructor nil)
    (:constructor make-undo-tree
       (&optional timestamp+flag
                  &aux
                    (root (undo-tree-make-node nil nil nil timestamp+flag))
                    (current root)
                    (size 0)
                    (count 0)
                    (object-pool (make-hash-table :test 'eq :weakness 'value))
                    (previous root))))
  root current size count object-pool previous)

;;; Use `symbol-function' to inspect the value.
;;;
;;; Common methods to obtain a NODE:
;;; -  (undo-tree-root undo-tree-list)
;;; -  (undo-tree-current undo-tree-list)
;;; -  (undo-tree-previous undo-tree-list)
;;; -  (nth N (undo-tree-node-next NODE))
;;; -  (undo-tree-node-previous NODE)
;;;
;;; `undo-tree-node-previous':  Always a vector.
;;;                             nth 0 index of the NODE array.
;;;                             (aref NODE 0)
;;;                             (undo-tree-node-previous NODE)
;;;
;;; `undo-tree-node-next':  A list of one or more nodes, or `nil` if it is a leaf.
;;;                         Each element of the list is a vector.
;;;                         nth 1 index of the NODE array.
;;;                         (aref NODE 1)
;;;                         (undo-tree-node-next NODE)
;;;
;;; `undo-tree-node-undo':  nth 2 index of the NODE array.
;;;                         (aref NODE 2)
;;;                         (undo-tree-node-undo NODE)
;;;
;;; `undo-tree-node-redo':  nth 3 index of the NODE array.
;;;                         (aref NODE 3)
;;;                         (undo-tree-node-redo NODE)
;;;
;;; `undo-tree-node-timestamp':  nth 4 index of the NODE array.
;;;                              (aref NODE 4)
;;;                              (undo-tree-node-timestamp NODE)
;;;
;;; `undo-tree-node-branch':  nth 5 index of the NODE array.
;;;                           (aref NODE 5)
;;;                           (undo-tree-node-branch NODE)
;;;
;;; `undo-tree-node-meta-data':  nth 6 index of the NODE array.
;;;                              (aref NODE 6)
;;;                              (undo-tree-node-meta-data NODE)
;;;
;;; `undo-tree-node-history':  nth 7 index of the NODE array.
;;;                            (aref NODE 7)
;;;                            (undo-tree-node-history NODE)
;;;
;;; `undo-tree-node-count':  nth 8 index of the NODE array.
;;;                          (aref NODE 8)
;;;                          (undo-tree-node-count NODE)
;;;
;;; `undo-tree-node-position':  nth 9 index of the NODE array.
;;;                             (aref NODE 9)
;;;                             (undo-tree-node-position NODE)
;;;
(cl-defstruct
  (undo-tree-node
    (:type vector)   ; create unnamed struct
    (:constructor nil)
    (:constructor undo-tree-make-node
       (previous undo
       &optional redo timestamp+flag
       &aux (timestamp (current-time))
            (branch 0)
            (history
              (cond
                ;;; a regular timestamp with 4 elements.
                ((and timestamp+flag
                      (drew-adams--true-listp timestamp+flag)
                      (= (length timestamp+flag) 4))
                  (list (cons timestamp+flag nil)))
                ;;; a `cons' cell, the `car' of which is a regular timestmap
                ;;; with 4 elements, and an optional `cdr' of `nil` or `t`.
                ((and timestamp+flag
                      (not (drew-adams--true-listp timestamp+flag)))
                  (list timestamp+flag))
                (t
                  nil)))))
    (:constructor undo-tree-make-node-backwards
       (next-node undo
       &optional redo timestamp+flag
       &aux (next (list next-node))
            (timestamp (current-time))
            (branch 0)
            (history
              (cond
                ;;; a regular timestamp with 4 elements.
                ((and timestamp+flag
                      (drew-adams--true-listp timestamp+flag)
                      (= (length timestamp+flag) 4))
                  (list (cons timestamp+flag nil)))
                ;;; a `cons' cell, the `car' of which is a regular timestmap
                ;;; with 4 elements, and an optional `cdr' of `nil` or `t`.
                ((and timestamp+flag
                      (not (drew-adams--true-listp timestamp+flag)))
                  (list timestamp+flag))
                (t
                  nil)))))
    (:copier nil))
  previous next undo redo timestamp branch meta-data history count position)

;;; Use `symbol-function' to inspect the value.
;;; `undo-tree-region-data-undo-beginning'
;;; `undo-tree-region-data-undo-end'
;;; `undo-tree-region-data-redo-beginning'
;;; `undo-tree-region-data-redo-end'
(cl-defstruct
  (undo-tree-region-data
   (:type vector)   ; create unnamed struct
   (:constructor nil)
   (:constructor undo-tree-make-region-data
     (&optional undo-beginning undo-end redo-beginning redo-end))
   (:constructor undo-tree-make-undo-region-data (undo-beginning undo-end))
   (:constructor undo-tree-make-redo-region-data (redo-beginning redo-end))
   (:copier nil))
  undo-beginning undo-end redo-beginning redo-end)

(defsetf undo-tree-node-undo-beginning (node) (val)
  `(let ((r (plist-get (undo-tree-node-meta-data ,node) :region)))
     (unless (undo-tree-region-data-p r)
       (setf (undo-tree-node-meta-data ,node)
       (plist-put (undo-tree-node-meta-data ,node) :region
      (setq r (undo-tree-make-region-data)))))
     (setf (undo-tree-region-data-undo-beginning r) ,val)))

(defsetf undo-tree-node-undo-end (node) (val)
  `(let ((r (plist-get (undo-tree-node-meta-data ,node) :region)))
     (unless (undo-tree-region-data-p r)
       (setf (undo-tree-node-meta-data ,node)
       (plist-put (undo-tree-node-meta-data ,node) :region
      (setq r (undo-tree-make-region-data)))))
     (setf (undo-tree-region-data-undo-end r) ,val)))

(defsetf undo-tree-node-redo-beginning (node) (val)
  `(let ((r (plist-get (undo-tree-node-meta-data ,node) :region)))
     (unless (undo-tree-region-data-p r)
       (setf (undo-tree-node-meta-data ,node)
       (plist-put (undo-tree-node-meta-data ,node) :region
      (setq r (undo-tree-make-region-data)))))
     (setf (undo-tree-region-data-redo-beginning r) ,val)))

(defsetf undo-tree-node-redo-end (node) (val)
  `(let ((r (plist-get (undo-tree-node-meta-data ,node) :region)))
     (unless (undo-tree-region-data-p r)
       (setf (undo-tree-node-meta-data ,node)
       (plist-put (undo-tree-node-meta-data ,node) :region
      (setq r (undo-tree-make-region-data)))))
     (setf (undo-tree-region-data-redo-end r) ,val)))

;;; Use `symbol-function' to inspect the value.
;;; `undo-tree-visual-data-lwidth'
;;; `undo-tree-visual-data-cwidth'
;;; `undo-tree-visual-data-rwidth'
;;; `undo-tree-visual-data-marker'
(cl-defstruct
  (undo-tree-visual-data
   (:type vector)   ; create unnamed struct
   (:constructor nil)
   (:constructor undo-tree-make-visual-data
     (&optional lwidth cwidth rwidth marker))
   (:copier nil))
  lwidth cwidth rwidth marker)

(defsetf undo-tree-node-lwidth (node) (val)
  `(let ((v (plist-get (undo-tree-node-meta-data ,node) :visual)))
     (unless (undo-tree-visual-data-p v)
       (setf (undo-tree-node-meta-data ,node)
       (plist-put (undo-tree-node-meta-data ,node) :visual
      (setq v (undo-tree-make-visual-data)))))
     (setf (undo-tree-visual-data-lwidth v) ,val)))

(defsetf undo-tree-node-cwidth (node) (val)
  `(let ((v (plist-get (undo-tree-node-meta-data ,node) :visual)))
     (unless (undo-tree-visual-data-p v)
       (setf (undo-tree-node-meta-data ,node)
       (plist-put (undo-tree-node-meta-data ,node) :visual
      (setq v (undo-tree-make-visual-data)))))
     (setf (undo-tree-visual-data-cwidth v) ,val)))

(defsetf undo-tree-node-rwidth (node) (val)
  `(let ((v (plist-get (undo-tree-node-meta-data ,node) :visual)))
     (unless (undo-tree-visual-data-p v)
       (setf (undo-tree-node-meta-data ,node)
       (plist-put (undo-tree-node-meta-data ,node) :visual
      (setq v (undo-tree-make-visual-data)))))
     (setf (undo-tree-visual-data-rwidth v) ,val)))

(defsetf undo-tree-node-marker (node) (val)
  `(let ((v (plist-get (undo-tree-node-meta-data ,node) :visual)))
     (unless (undo-tree-visual-data-p v)
       (setf (undo-tree-node-meta-data ,node)
       (plist-put (undo-tree-node-meta-data ,node) :visual
      (setq v (undo-tree-make-visual-data)))))
     (setf (undo-tree-visual-data-marker v) ,val)))

;;; Use `symbol-function' to inspect the value.
;;; `undo-tree-register-data-buffer'
;;; `undo-tree-register-data-node'
(cl-defstruct
  (undo-tree-register-data
   (:type vector)
   (:constructor nil)
   (:constructor undo-tree-make-register-data (buffer node)))
  buffer node)

(defsetf undo-tree-node-register (node) (val)
  `(setf (undo-tree-node-meta-data ,node)
   (plist-put (undo-tree-node-meta-data ,node) :register ,val)))

(defmacro undo-tree-node-p (n)
  (let ((len (length (undo-tree-make-node nil nil))))
    `(and (vectorp ,n) (= (length ,n) ,len))))

(defmacro undo-tree-region-data-p (r)
  (let ((len (length (undo-tree-make-region-data))))
    `(and (vectorp ,r) (= (length ,r) ,len))))

(defmacro undo-tree-node-clear-region-data (node)
  `(setf (undo-tree-node-meta-data ,node)
   (delq nil
         (delq :region
         (plist-put (undo-tree-node-meta-data ,node)
        :region nil)))))

(defmacro undo-tree-node-undo-beginning (node)
  `(let ((r (plist-get (undo-tree-node-meta-data ,node) :region)))
     (when (undo-tree-region-data-p r)
       (undo-tree-region-data-undo-beginning r))))

(defmacro undo-tree-node-undo-end (node)
  `(let ((r (plist-get (undo-tree-node-meta-data ,node) :region)))
     (when (undo-tree-region-data-p r)
       (undo-tree-region-data-undo-end r))))

(defmacro undo-tree-node-redo-beginning (node)
  `(let ((r (plist-get (undo-tree-node-meta-data ,node) :region)))
     (when (undo-tree-region-data-p r)
       (undo-tree-region-data-redo-beginning r))))

(defmacro undo-tree-node-redo-end (node)
  `(let ((r (plist-get (undo-tree-node-meta-data ,node) :region)))
     (when (undo-tree-region-data-p r)
       (undo-tree-region-data-redo-end r))))

(defmacro undo-tree-visual-data-p (v)
  (let ((len (length (undo-tree-make-visual-data))))
    `(and (vectorp ,v) (= (length ,v) ,len))))

(defun undo-tree-node-clear-visual-data (node)
  (let ((plist (undo-tree-node-meta-data node)))
    (if (eq (car plist) :visual)
  (setf (undo-tree-node-meta-data node) (nthcdr 2 plist))
      (while (and plist (not (eq (cadr plist) :visual)))
  (setq plist (cdr plist)))
      (if plist (setcdr plist (nthcdr 3 plist))))))

(defmacro undo-tree-node-lwidth (node)
  `(let ((v (plist-get (undo-tree-node-meta-data ,node) :visual)))
     (when (undo-tree-visual-data-p v)
       (undo-tree-visual-data-lwidth v))))

(defmacro undo-tree-node-cwidth (node)
  `(let ((v (plist-get (undo-tree-node-meta-data ,node) :visual)))
     (when (undo-tree-visual-data-p v)
       (undo-tree-visual-data-cwidth v))))

(defmacro undo-tree-node-rwidth (node)
  `(let ((v (plist-get (undo-tree-node-meta-data ,node) :visual)))
     (when (undo-tree-visual-data-p v)
       (undo-tree-visual-data-rwidth v))))

(defmacro undo-tree-node-marker (node)
  `(let ((v (plist-get (undo-tree-node-meta-data ,node) :visual)))
     (when (undo-tree-visual-data-p v)
       (undo-tree-visual-data-marker v))))

(defun undo-tree-register-data-p (data)
  (and (vectorp data)
       (= (length data) 2)
       (undo-tree-node-p (undo-tree-register-data-node data))))

(defun undo-tree-register-data-print-func (data)
  (princ (format "an undo-tree state for buffer %s"
     (undo-tree-register-data-buffer data))))

(defmacro undo-tree-node-register (node)
  `(plist-get (undo-tree-node-meta-data ,node) :register))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Basic undo-tree data structure functions

(defun undo-tree-grow-backwards (node undo &optional redo timestamp+flag)
"Add new node *above* undo-tree NODE, and return new node.
Note that this will overwrite NODE's \"previous\" link, so should
only be used on a detached NODE, never on nodes that are already
part of `undo-tree-list'.
TIMESTAMP+FLAG is a `cons' cell with the timestamp as the `car' and
the optional flag as the `cdr'."
  (let ((new (undo-tree-make-node-backwards node undo redo timestamp+flag)))
    (setf (undo-tree-node-previous node) new)
    new))

(defun undo-tree-splice-node (node splice)
"Splice NODE into undo tree, below node SPLICE.
Note that this will overwrite NODE's \"next\" and \"previous\"
links, so should only be used on a detached NODE, never on nodes
that are already part of `undo-tree-list'."
  (setf (undo-tree-node-next node) (undo-tree-node-next splice)
  (undo-tree-node-branch node) (undo-tree-node-branch splice)
  (undo-tree-node-previous node) splice
  (undo-tree-node-next splice) (list node)
  (undo-tree-node-branch splice) 0)
  (dolist (n (undo-tree-node-next node))
    (setf (undo-tree-node-previous n) node)))

(defun undo-tree-snip-node (node)
"Snip NODE out of undo tree."
  (let* ((parent (undo-tree-node-previous node))
   position p)
    ;; if NODE is only child, replace parent's next links with NODE's
    (if (= (length (undo-tree-node-next parent)) 0)
  (setf (undo-tree-node-next parent) (undo-tree-node-next node)
        (undo-tree-node-branch parent) (undo-tree-node-branch node))
      ;; otherwise...
      (setq position (undo-tree-position node (undo-tree-node-next parent)))
      (cond
       ;; if active branch used do go via NODE, set parent's branch to active
       ;; branch of NODE
       ((= (undo-tree-node-branch parent) position)
  (setf (undo-tree-node-branch parent)
        (+ position (undo-tree-node-branch node))))
       ;; if active branch didn't go via NODE, update parent's branch to point
       ;; to same node as before
       ((> (undo-tree-node-branch parent) position)
         (incf (undo-tree-node-branch parent) (1- (length (undo-tree-node-next node))))))
      ;; replace NODE in parent's next list with NODE's entire next list
      (if (= position 0)
    (setf (undo-tree-node-next parent)
    (nconc (undo-tree-node-next node)
           (cdr (undo-tree-node-next parent))))
  (setq p (nthcdr (1- position) (undo-tree-node-next parent)))
  (setcdr p (nconc (undo-tree-node-next node) (cddr p)))))
    ;; update previous links of NODE's children
    (dolist (n (undo-tree-node-next node))
      (setf (undo-tree-node-previous n) parent))))

(defun undo-tree-mapc (--undo-tree-mapc-function-- node)
"Apply FUNCTION to NODE and to each node below it."
  (let ((stack (list node))
  n)
    (while stack
      (setq n (pop stack))
      (funcall --undo-tree-mapc-function-- n)
      (setq stack (append (undo-tree-node-next n) stack)))))

(defmacro undo-tree-num-branches ()
"Return number of branches at current undo tree node."
  '(length (undo-tree-node-next (undo-tree-current undo-tree-list))))

(defun undo-tree-position (node list)
"Find the first occurrence of NODE in LIST.
Return the index of the matching item, or nil of not found.
Comparison is done with `eq'."
  (let ((i 0))
    (catch 'found
      (while (progn
               (when (eq node (car list)) (throw 'found i))
               (incf i)
               (setq list (cdr list))))
      nil)))

(defmacro undo-tree-generate-id ()
"Generate a new, unique id (uninterned symbol).
The name is made by appending a number to `undo-tree-id`.
Copied from CL package `gensym'."
  `(let ((num (prog1 *undo-tree-id-counter* (incf *undo-tree-id-counter*))))
     (make-symbol (format "undo-tree-id%d" num))))

(defun undo-tree-decircle (undo-tree)
"Nullify PREVIOUS links of UNDO-TREE nodes, to make UNDO-TREE data structure non-circular."
  (undo-tree-mapc
    (lambda (node)
      (dolist (n (undo-tree-node-next node))
        (setf (undo-tree-node-previous n) nil)))
    (undo-tree-root undo-tree)))

(defun undo-tree-recircle (undo-tree)
"Recreate PREVIOUS links of UNDO-TREE nodes, to restore circular UNDO-TREE data structure."
  (undo-tree-mapc
    (lambda (node)
      (dolist (n (undo-tree-node-next node))
        (setf (undo-tree-node-previous n) node)))
    (undo-tree-root undo-tree)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Undo list and undo changeset utility functions

(defmacro undo-tree-marker-elt-p (elt)
  `(markerp (car-safe ,elt)))

(defmacro undo-tree-GCd-marker-elt-p (elt)
"Return t if ELT is a marker element whose marker has been moved to the
object-pool, so may potentially have been garbage-collected.
Note: Valid marker undo elements should be uniquely identified as cons
cells with a symbol in the car (replacing the marker), and a number in
the cdr. However, to guard against future changes to undo element
formats, we perform an additional redundant check on the symbol name."
  `(and (car-safe ,elt)
  (symbolp (car ,elt))
  (let ((str (symbol-name (car ,elt))))
    (and (> (length str) 12)
         (string= (substring str 0 12) "undo-tree-id")))
  (numberp (cdr-safe ,elt))))

(defun undo-tree-move-GC-elts-to-pool (elt)
"Move elements that can be garbage-collected into `undo-tree-list'
object pool, substituting a unique id that can be used to retrieve them
later.  Only markers require this treatment currently."
  (when (undo-tree-marker-elt-p elt)
    (let ((id (undo-tree-generate-id))
          (hash-table (undo-tree-object-pool undo-tree-list)))
      (unless hash-table
        (let ((debug-on-quit nil))
          (signal 'quit '("undo-tree-move-GC-elts-to-pool:  The hash table is `nil`!"))))
      (puthash id (car elt) hash-table)
      (setcar elt id))))

(defun undo-tree-restore-GC-elts-from-pool (elt)
"Replace object id's in ELT with corresponding objects from
`undo-tree-list' object pool and return modified ELT, or return nil if
any object in ELT has been garbage-collected."
  (if (undo-tree-GCd-marker-elt-p elt)
    (let ((hash-table (undo-tree-object-pool undo-tree-list)))
      (unless hash-table
        (let ((debug-on-quit nil))
          (signal 'quit '("undo-tree-restore-GC-elts-from-pool:  The hash table is `nil`!"))))
      (when (setcar elt (gethash (car elt) hash-table))
        elt))
    elt))

(defun undo-tree-clean-GCd-elts (undo-list)
"Remove object id's from UNDO-LIST that refer to elements that have been
garbage-collected. UNDO-LIST is modified by side-effect."
  (let ((hash-table (undo-tree-object-pool undo-tree-list)))
    (unless hash-table
      (let ((debug-on-quit nil))
        (signal 'quit '("undo-tree-clean-GCd-elts:  The hash table is `nil`!"))))
    (while (undo-tree-GCd-marker-elt-p (car undo-list))
      (unless (gethash (caar undo-list) hash-table)
        (setq undo-list (cdr undo-list))))
    (let ((p undo-list))
      (while (cdr p)
        (when (and (undo-tree-GCd-marker-elt-p (cadr p))
                   (null (gethash (car (cadr p)) hash-table)))
          (setcdr p (cddr p)))
        (setq p (cdr p))))
    undo-list))

(defun undo-tree-pop-changeset (&optional discard-pos)
"Pop changeset from `buffer-undo-list'. If DISCARD-POS is non-nil, discard
any position entries from changeset.
Discard undo boundaries and, if DISCARD-POS is non-nil, position entries
at head of undo list."
  (while (or (null (car buffer-undo-list))
             (and discard-pos (integerp (car buffer-undo-list))))
    (setq buffer-undo-list (cdr buffer-undo-list)))
  ;; pop elements up to next undo boundary, discarding position entries if
  ;; DISCARD-POS is non-nil
  (if (eq (car buffer-undo-list) 'undo-tree-canary)
      (push nil buffer-undo-list)
    (let* ((changeset (list (pop buffer-undo-list)))
           (p changeset))
      (while (progn
               (undo-tree-move-GC-elts-to-pool (car p))
               (while (and discard-pos (integerp (car buffer-undo-list)))
                 (setq buffer-undo-list (cdr buffer-undo-list)))
               (and (car buffer-undo-list)
                    (not (eq (car buffer-undo-list) 'undo-tree-canary))))
        (setcdr p (list (pop buffer-undo-list)))
        (setq p (cdr p)))
      changeset)))

(defun undo-tree-copy-list (undo-list)
"Return a deep copy of first changeset in `undo-list'. Object id's are
replaced by corresponding objects from `undo-tree-list' object-pool."
  (let (copy p)
      ;; if first element contains an object id, replace it with object from
      ;; pool, discarding element entirely if it's been GC'd
    (while (and undo-list (null copy))
      (setq copy (undo-tree-restore-GC-elts-from-pool (pop undo-list))))
    (when copy
      (setq copy (list copy)
            p copy)
      ;; copy remaining elements, replacing object id's with objects from
      ;; pool, or discarding them entirely if they've been GC'd
      (while undo-list
        (when (setcdr p (undo-tree-restore-GC-elts-from-pool
                          (undo-copy-list-1 (pop undo-list))))
          (setcdr p (list (cdr p)))
          (setq p (cdr p))))
      copy)))

(defun undo-tree-byte-size (undo-list)
"Return size (in bytes) of UNDO-LIST."
  (let ((size 0) (p undo-list))
    (while p
      (incf size 8)  ; cons cells use up 8 bytes
      (when (and (consp (car p)) (stringp (caar p)))
        (incf size (string-bytes (caar p))))
      (setq p (cdr p)))
    size))

(defun undo-tree-rebuild-undo-list ()
"Rebuild `buffer-undo-list' from information in `undo-tree-list'."
  (unless (eq buffer-undo-list t)
    (undo-tree-transfer-list)
    (setq buffer-undo-list nil)
    (when undo-tree-list
      (let ((stack (list (list (undo-tree-root undo-tree-list)))))
  (push (sort (mapcar 'identity (undo-tree-node-next (caar stack)))
        (lambda (a b)
          (time-less-p (undo-tree-node-timestamp a)
           (undo-tree-node-timestamp b))))
        stack)
  ;; Traverse tree in depth-and-oldest-first order, but add undo records
  ;; on the way down, and redo records on the way up.
  (while (or (car stack)
       (not (eq (car (nth 1 stack))
          (undo-tree-current undo-tree-list))))
    (if (car stack)
        (progn
    (setq buffer-undo-list
          (append (undo-tree-node-undo (caar stack))
            buffer-undo-list))
    (undo-boundary)
    (push (sort (mapcar 'identity
            (undo-tree-node-next (caar stack)))
          (lambda (a b)
            (time-less-p (undo-tree-node-timestamp a)
             (undo-tree-node-timestamp b))))
          stack))
      (pop stack)
      (setq buffer-undo-list
      (append (undo-tree-node-redo (caar stack))
        buffer-undo-list))
      (undo-boundary)
      (pop (car stack))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; History discarding utility functions

(defun undo-tree-oldest-leaf (node)
"Return oldest leaf node below NODE."
  (while (undo-tree-node-next node)
    (setq node
          (car (sort (mapcar 'identity (undo-tree-node-next node))
                     (lambda (a b)
                       (time-less-p (undo-tree-node-timestamp a)
                                    (undo-tree-node-timestamp b)))))))
  node)

(defun undo-tree-discard-node (node)
"Discard NODE from `undo-tree-list', and return next in line for discarding.
Don't discard current node."
  (unless (eq node (undo-tree-current undo-tree-list))
    ;; discarding root node...
    (if (eq node (undo-tree-root undo-tree-list))
        (cond
         ;; should always discard branches before root
         ((> (length (undo-tree-node-next node)) 1)
          (error "Trying to discard undo-tree root which still has multiple branches"))
         ;; don't discard root if current node is only child
         ((eq (car (undo-tree-node-next node))
              (undo-tree-current undo-tree-list))
    nil)
   ;; discard root
         (t
    ;; clear any register referring to root
    (let ((r (undo-tree-node-register node)))
      (when (and r (eq (get-register r) node))
        (set-register r nil)))
          ;; make child of root into new root
          (setq node (setf (undo-tree-root undo-tree-list)
                           (car (undo-tree-node-next node))))
    ;; update undo-tree size
    (decf (undo-tree-size undo-tree-list)
            (+ (undo-tree-byte-size (undo-tree-node-undo node))
               (undo-tree-byte-size (undo-tree-node-redo node))))
    (decf (undo-tree-count undo-tree-list))
    ;; discard new root's undo data and PREVIOUS link
    (setf (undo-tree-node-undo node) nil
    (undo-tree-node-redo node) nil
    (undo-tree-node-previous node) nil)
          ;; if new root has branches, or new root is current node, next node
          ;; to discard is oldest leaf, otherwise it's new root
          (if (or (> (length (undo-tree-node-next node)) 1)
                  (eq (car (undo-tree-node-next node))
                      (undo-tree-current undo-tree-list)))
              (undo-tree-oldest-leaf node)
            node)))
      ;; discarding leaf node...
      (let* ((parent (undo-tree-node-previous node))
             (current (nth (undo-tree-node-branch parent)
                           (undo-tree-node-next parent))))
  ;; clear any register referring to the discarded node
  (let ((r (undo-tree-node-register node)))
    (when (and r (eq (get-register r) node))
      (set-register r nil)))
  ;; update undo-tree size
  (decf (undo-tree-size undo-tree-list)
          (+ (undo-tree-byte-size (undo-tree-node-undo node))
             (undo-tree-byte-size (undo-tree-node-redo node))))
  (decf (undo-tree-count undo-tree-list))
  ;; discard leaf
        (setf (undo-tree-node-next parent)
                (delq node (undo-tree-node-next parent))
              (undo-tree-node-branch parent)
                (undo-tree-position current (undo-tree-node-next parent)))
        ;; if parent has branches, or parent is current node, next node to
        ;; discard is oldest leaf, otherwise it's the parent itself
        (if (or (eq parent (undo-tree-current undo-tree-list))
                (and (undo-tree-node-next parent)
                     (or (not (eq parent (undo-tree-root undo-tree-list)))
                         (> (length (undo-tree-node-next parent)) 1))))
            (undo-tree-oldest-leaf parent)
          parent)))))

(defun undo-tree-discard-history--one-of-two ()
"This is similar to `truncate_undo_list' defined in `undo.c`, but meant to be used
with the `undo-tree` library to keep the `undo-tree-list' at a reasonable size.
It appears that Dr. Cubitt chose to use a similar methodology by utilizing the same
built-in variables mentioned hereinbelow.  Although the `undo-tree-list' can be
exported to a file and its file size is a consideration, the size of the buffer-
local variable itself is the primary concern here as it occupies system memory.
Discard undo history until we're within memory usage limits set by `undo-tree--undo-limit',
`undo-tree--undo-strong-limit' and `undo-tree--undo-outer-limit'."
  (when (> (undo-tree-size undo-tree-list) undo-tree--undo-limit)
    ;; if there are no branches off root, first node to discard is root;
    ;; otherwise it's leaf node at botom of oldest branch
    (let* ((undo-tree-oldest-leaf--variable nil)
           (undo-tree-root--variable nil)
           (node (if (> (length (undo-tree-node-next (undo-tree-root undo-tree-list))) 1)
                   (setq undo-tree-oldest-leaf--variable
                           (undo-tree-oldest-leaf (undo-tree-root undo-tree-list)))
                   (setq undo-tree-root--variable
                           (undo-tree-root undo-tree-list))))
           (type-of-node
             (cond
               (undo-tree-oldest-leaf--variable
                 "leaf of oldest branch")
               (undo-tree-root--variable
                 "root")))
           (count--undo-strong-limit 0)
           (count--undo-limit 0))
      ;; discard nodes until memory use is within `undo-tree--undo-strong-limit'
      (while (and node
                  (> (undo-tree-size undo-tree-list) undo-tree--undo-strong-limit))
        (setq node (undo-tree-discard-node node))
        (incf count--undo-strong-limit))
      (when (> count--undo-strong-limit 0)
        (message "undo-tree-discard-history--one-of-two:  `undo-tree--undo-strong-limit' -- discarded (%s) nodes from the `%s`."
                 count--undo-strong-limit type-of-node))
      ;; discard nodes until next node to discard would bring memory use within `undo-tree--undo-limit'
      (while (and node
                  ;; check first if last discard has brought us within
                  ;; `undo-tree--undo-limit', in case we can avoid more expensive `undo-tree--undo-strong-limit' calculation
                  ;; Note: this assumes undo-tree--undo-strong-limit > undo-tree--undo-limit;
                  ;;       if not, effectively undo-tree--undo-strong-limit = undo-tree--undo-limit
                  (> (undo-tree-size undo-tree-list) undo-tree--undo-limit)
                  (> (- (undo-tree-size undo-tree-list)
                        ;; if next node to discard is root, the memory we
                        ;; free-up comes from discarding changesets from its
                        ;; only child...
                        (if (eq node (undo-tree-root undo-tree-list))
                          (+ (undo-tree-byte-size
                               (undo-tree-node-undo (car (undo-tree-node-next node))))
                             (undo-tree-byte-size
                               (undo-tree-node-redo (car (undo-tree-node-next node)))))
                          ;; ...otherwise, it comes from discarding changesets
                          ;; from along with the node itself
                          (+ (undo-tree-byte-size (undo-tree-node-undo node))
                             (undo-tree-byte-size (undo-tree-node-redo node)))))
                     undo-tree--undo-limit))
        (setq node (undo-tree-discard-node node))
        (incf count--undo-limit))
      (when (> count--undo-limit 0)
        (message "undo-tree-discard-history--one-of-two:  `undo-tree--undo-limit' -- discarded (%s) nodes from the `%s`."
                 count--undo-limit type-of-node))
      ;; if we're still over the `undo-tree--undo-outer-limit', discard entire history
      (when (> (undo-tree-size undo-tree-list) undo-tree--undo-outer-limit)
        ;; query first if `undo-ask-before-discard' is set
        (if undo-ask-before-discard
          (when (y-or-n-p
                 (format
                  "Buffer `%s' undo info is %d bytes long;  discard it? "
                  (buffer-name) (undo-tree-size undo-tree-list)))
            (setq undo-tree-list nil))
          ;; otherwise, discard and display warning
          (display-warning
           '(undo-tree discard-info)
           (concat
            (format "Buffer `%s' undo info was %d bytes long.\n"
                    (buffer-name) (undo-tree-size undo-tree-list))
"The undo info was discarded because it exceeded `undo-tree--undo-outer-limit'.\n
-  This is normal if you executed a command that made a huge change
to the buffer. In that case, to prevent similar problems in the
future, set `undo-tree--undo-outer-limit' to a value that is large
enough to cover the maximum size of normal changes you expect a
single command to make, but not so large that it might exceed the
maximum memory allotted to Emacs.\n
-  If you did not execute any such command, the situation is
probably due to a bug and you should report it.\n
-  You can disable the popping up of this buffer by adding the entry
\(undo discard-info) to the user option `warning-suppress-types',
which is defined in the `warnings' library.\n")
           :warning)
          (setq undo-tree-list nil))))))

(defun undo-tree-discard-history--two-of-two ()
"Workaround for Emacs bug 27571:  http://debbugs.gnu.org/cgi/bugreport.cgi?bug=27571
Emacs crashes when calling `undo-tree-history-save' on a large `undo-tree-list'.
Truncate the `undo-tree-list' if the number of nodes would exceed a specific number (6651).
A better solution is to set the ulimit stack size before starting Emacs using a bash script:
#!/bin/sh
ulimit -S -s unlimited
/Applications/Emacs.app/Contents/MacOS/Emacs &"
  (when (> (undo-tree-count undo-tree-list) 6500)
    ;; if there are no branches off root, first node to discard is root;
    ;; otherwise it's leaf node at botom of oldest branch
    (let* ((undo-tree-oldest-leaf--variable nil)
           (undo-tree-root--variable nil)
           (node (if (> (length (undo-tree-node-next (undo-tree-root undo-tree-list))) 1)
                   (setq undo-tree-oldest-leaf--variable
                           (undo-tree-oldest-leaf (undo-tree-root undo-tree-list)))
                   (setq undo-tree-root--variable
                           (undo-tree-root undo-tree-list))))
           (type-of-node
             (cond
               (undo-tree-oldest-leaf--variable
                 "leaf of oldest branch")
               (undo-tree-root--variable
                 "root")))
           (count--discarded 0))
      ;; discard nodes until print limit is within 6500.
      (while (and node
                  (> (undo-tree-count undo-tree-list) 6500))
        (setq node (undo-tree-discard-node node))
        (incf count--discarded))
      (when (> count--discarded 0)
        (message "undo-tree-discard-history--two-of-two:  discarded (%s) nodes from the `%s`."
                 count--discarded type-of-node)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Undo-in-region utility functions

(defun undo-tree-adjust-elements-to-elt (node undo-elt &optional below)
"Adjust buffer positions of undo elements, starting at NODE's
and going up the tree (or down the active branch if BELOW is
non-nil) and through the nodes' undo elements until we reach
UNDO-ELT.  UNDO-ELT must appear somewhere in the undo changeset
of either NODE itself or some node above it in the tree."
  (let ((delta (list (undo-delta undo-elt)))
  (undo-list (undo-tree-node-undo node)))
    ;; adjust elements until we reach UNDO-ELT
    (while (and (car undo-list)
    (not (eq (car undo-list) undo-elt)))
      (setcar undo-list
        (undo-tree-apply-deltas (car undo-list) delta -1))
      ;; move to next undo element in list, or to next node if we've run out
      ;; of elements
      (unless (car (setq undo-list (cdr undo-list)))
  (if below
      (setq node (nth (undo-tree-node-branch node)
          (undo-tree-node-next node)))
    (setq node (undo-tree-node-previous node)))
  (setq undo-list (undo-tree-node-undo node))))))

(defun undo-tree-apply-deltas (undo-elt deltas &optional sgn)
"Apply DELTAS in order to UNDO-ELT, multiplying deltas by SGN.
Only useful value for SGN is -1."
  (let (position offset)
    (dolist (delta deltas)
      (setq position (car delta)
      offset (* (cdr delta) (or sgn 1)))
      (cond
       ;; POSITION
       ((integerp undo-elt)
  (when (>= undo-elt position)
    (setq undo-elt (- undo-elt offset))))
       ;; nil (or any other atom)
       ((atom undo-elt))
       ;; (TEXT . POSITION)
       ((stringp (car undo-elt))
  (let ((text-pos (abs (cdr undo-elt)))
        (point-at-end (< (cdr undo-elt) 0)))
    (if (>= text-pos position)
        (setcdr undo-elt (* (if point-at-end -1 1)
          (- text-pos offset))))))
       ;; (BEGIN . END)
       ((integerp (car undo-elt))
  (when (>= (car undo-elt) position)
    (setcar undo-elt (- (car undo-elt) offset))
    (setcdr undo-elt (- (cdr undo-elt) offset))))
       ;; (nil PROPERTY VALUE BEG . END)
       ((null (car undo-elt))
  (let ((tail (nthcdr 3 undo-elt)))
    (when (>= (car tail) position)
      (setcar tail (- (car tail) offset))
      (setcdr tail (- (cdr tail) offset)))))
       ))
    undo-elt))

(defun undo-tree-repeated-undo-in-region-p (start end)
"Return non-nil if undo-in-region between START and END is a repeated undo-in-region."
  (let ((node (undo-tree-current undo-tree-list)))
    (and (setq node (nth (undo-tree-node-branch node) (undo-tree-node-next node)))
         (eq (undo-tree-node-undo-beginning node) start)
         (eq (undo-tree-node-undo-end node) end))))

(defun undo-tree-repeated-redo-in-region-p (start end)
"Return non-nil if undo-in-region between START and END is a repeated undo-in-region."
  (let ((node (undo-tree-current undo-tree-list)))
    (and (eq (undo-tree-node-redo-beginning node) start)
         (eq (undo-tree-node-redo-end node) end))))


(defalias 'undo-tree-reverting-undo-in-region-p 'undo-tree-repeated-undo-in-region-p
"Return non-nil if undo-in-region between START and END is simply reverting the
last redo-in-region.")

(defalias 'undo-tree-reverting-redo-in-region-p 'undo-tree-repeated-redo-in-region-p
"Return non-nil if redo-in-region between START and END is simply reverting the
last undo-in-region.")

(defun undo-tree-pull-undo-in-region-branch (start end)
"Pull out entries from undo changesets to create a new undo-in-region
branch, which undoes changeset entries lying between START and END first,
followed by remaining entries from the changesets, before rejoining the
existing undo tree history. Repeated calls will, if appropriate, extend
the current undo-in-region branch rather than creating a new one.
if we're just reverting the last redo-in-region, we don't need to
manipulate the undo tree at all."
  (if (undo-tree-reverting-redo-in-region-p start end)
      t  ; return t to indicate success
    ;; We build the `region-changeset' and `delta-list' lists forwards, using
    ;; pointers `r' and `d' to the penultimate element of the list. So that we
    ;; don't have to treat the first element differently, we prepend a dummy
    ;; leading nil to the lists, and have the pointers point to that
    ;; initially.
    ;; Note: using '(nil) instead of (list nil) in the `let*' results in
    ;;       bizarre errors when the code is byte-compiled, where parts of the
    ;;       lists appear to survive across different calls to this function.
    ;;       An obscure byte-compiler bug, perhaps?
    (let* ((region-changeset (list nil))
           (r region-changeset)
           (delta-list (list nil))
           (d delta-list)
           (node (undo-tree-current undo-tree-list))
           (undo-tree--repeated-undo-in-region
             (undo-tree-repeated-undo-in-region-p start end))
           (undo-tree--new-undo-in-region
             (and (null undo-tree--repeated-undo-in-region)
                  (undo-tree-node-next node)))
           undo-tree-adjusted-markers  ; `undo-elt-in-region' expects this
           fragment splice original-fragment original-splice original-current
           got-visible-elt undo-list elt)
      ;; --- initialization ---
      (cond
        ;; if this is a repeated undo in the same region, start pulling changes
        ;; from NODE at which undo-in-region branch is attached, and detatch
        ;; the branch, using it as initial FRAGMENT of branch being constructed
        (undo-tree--repeated-undo-in-region
          (setq original-current node
                fragment (car (undo-tree-node-next node))
                splice node)
          ;; undo up to node at which undo-in-region branch is attached
          ;; (recognizable as first node with more than one branch)
          (let ((mark-active nil))
            (while (= (length (undo-tree-node-next node)) 1)
              (undo-tree--undo-or-redo nil 'undo nil nil nil)
              (setq fragment node
                    node (undo-tree-current undo-tree-list))))
          (when (eq splice node)
            (setq splice nil))
          ;; detatch undo-in-region branch
          (setf (undo-tree-node-next node) (delq fragment (undo-tree-node-next node))
                 (undo-tree-node-previous fragment) nil
                 original-fragment fragment
                 original-splice node))
        ;; if this is a new undo-in-region, initial FRAGMENT is a copy of all
        ;; nodes below the current one in the active branch
        (undo-tree--new-undo-in-region
          (setq fragment (undo-tree-make-node nil nil nil nil)
                splice fragment)
          (while (setq node (nth (undo-tree-node-branch node) (undo-tree-node-next node)))
            (let ((n (undo-tree-make-node
                       splice
                       (undo-copy-list (undo-tree-node-undo node))
                       (undo-copy-list (undo-tree-node-redo node))
                       nil)))
              (push n (undo-tree-node-next splice)))
            (setq splice (car (undo-tree-node-next splice))))
          (setq fragment (car (undo-tree-node-next fragment))
                splice nil
                node (undo-tree-current undo-tree-list))))
      ;; --- pull undo-in-region elements into branch ---
      ;; work backwards up tree, pulling out undo elements within region until
      ;; we've got one that undoes a visible change (insertion or deletion)
      (catch 'abort
        (while (and (not got-visible-elt) node (undo-tree-node-undo node))
          ;; we cons a dummy nil element on the front of the changeset so that
          ;; we can conveniently remove the first (real) element from the
          ;; changeset if we need to; the leading nil is removed once we're
          ;; done with this changeset
          (setq undo-list (cons nil (undo-copy-list (undo-tree-node-undo node)))
          elt (cadr undo-list))
          (if fragment
              (progn
                (setq fragment (undo-tree-grow-backwards fragment undo-list nil nil))
                (unless splice (setq splice fragment)))
            (setq fragment (undo-tree-make-node nil undo-list nil nil))
            (setq splice fragment))
          (while elt
            (cond
              ;; keep elements within region
              ((undo-elt-in-region elt start end)
                ;; set flag if kept element is visible (insertion or deletion)
                (when (and (consp elt)
                           (or (stringp (car elt)) (integerp (car elt))))
                  (setq got-visible-elt t))
                ;; adjust buffer positions in elements previously undone before
                ;; kept element, as kept element will now be undone first
                (undo-tree-adjust-elements-to-elt splice elt)
                ;; move kept element to undo-in-region changeset, adjusting its
                ;; buffer position as it will now be undone first
                (setcdr r (list (undo-tree-apply-deltas elt (cdr delta-list))))
                (setq r (cdr r))
                (setcdr undo-list (cddr undo-list)))
              ;; discard "was unmodified" elements
              ;; FIXME: deal properly with these
              ((and (consp elt) (eq (car elt) t))
                (setcdr undo-list (cddr undo-list)))
              ;; if element crosses region, we can't pull any more elements
              ((undo-elt-crosses-region elt start end)
                ;; if we've found a visible element, it must be earlier in
                ;; current node's changeset; stop pulling elements (null
                ;; `undo-list' and non-nil `got-visible-elt' cause loop to exit)
                (if got-visible-elt
                  (setq undo-list nil)
                  ;; if we haven't found a visible element yet, pulling
                  ;; undo-in-region branch has failed
                  (setq region-changeset nil)
                  (throw 'abort t)))
              ;; if rejecting element, add its delta (if any) to the list
              (t
                (let ((delta (undo-delta elt)))
                  (when (/= 0 (cdr delta))
                    (setcdr d (list delta))
                    (setq d (cdr d))))
                (setq undo-list (cdr undo-list))))
            ;; process next element of current changeset
            (setq elt (cadr undo-list)))
          ;; if there are remaining elements in changeset, remove dummy nil
          ;; from front
          (if (cadr (undo-tree-node-undo fragment))
            (pop (undo-tree-node-undo fragment))
            ;; otherwise, if we've kept all elements in changeset, discard
            ;; empty changeset
            (when (eq splice fragment) (setq splice nil))
            (setq fragment (car (undo-tree-node-next fragment))))
          ;; process changeset from next node up the tree
          (setq node (undo-tree-node-previous node)))) ;;; END `catch' / `while' loop.
      ;; pop dummy nil from front of `region-changeset'
      (setq region-changeset (cdr region-changeset))
      ;; --- integrate branch into tree ---
      ;; if no undo-in-region elements were found, restore undo tree
      (if (null region-changeset)
        (when original-current
          (push original-fragment (undo-tree-node-next original-splice))
          (setf (undo-tree-node-branch original-splice) 0
                 (undo-tree-node-previous original-fragment) original-splice)
          (let ((mark-active nil))
            (while (not (eq (undo-tree-current undo-tree-list) original-current))
              (undo-tree--undo-or-redo nil 'redo nil nil nil)))
          nil)  ; return nil to indicate failure
        ;; otherwise...
        ;; need to undo up to node where new branch will be attached, to ensure
        ;; redo entries are populated, and then redo back to where we started
        (let ((mark-active nil)
              (current (undo-tree-current undo-tree-list)))
          (while (not (eq (undo-tree-current undo-tree-list) node))
            (undo-tree--undo-or-redo nil 'undo nil nil nil))
          (while (not (eq (undo-tree-current undo-tree-list) current))
            (undo-tree--undo-or-redo nil 'redo nil nil nil)))
        (cond
          ;; if there's no remaining fragment, just create undo-in-region node
          ;; and attach it to parent of last node from which elements were pulled
          ((null fragment)
            ;;; DEBUGGING:  (message "wrap-it-up:  1 of 3")
            (setq fragment (undo-tree-make-node node region-changeset nil nil))
            (push fragment (undo-tree-node-next node))
            (setf (undo-tree-node-branch node) 0)
            ;; set current node to undo-in-region node
            (setf (undo-tree-current undo-tree-list) fragment))
          ;; if no splice point has been set, add undo-in-region node to top of
          ;; fragment and attach it to parent of last node from which elements were pulled
          ((null splice)
            ;;; DEBUGGING:  (message "wrap-it-up:  2 of 3")
            (setq fragment (undo-tree-grow-backwards fragment region-changeset nil nil))
            (push fragment (undo-tree-node-next node))
            (setf (undo-tree-node-branch node) 0
                   (undo-tree-node-previous fragment) node)
            ;; set current node to undo-in-region node
            (setf (undo-tree-current undo-tree-list) fragment))
          ;; if fragment contains nodes, attach fragment to parent of last node
          ;; from which elements were pulled, and splice in undo-in-region node
          (t
            ;;; DEBUGGING:  (message "wrap-it-up:  3 of 3")
            (setf (undo-tree-node-previous fragment) node)
            (push fragment (undo-tree-node-next node))
            (setf (undo-tree-node-branch node) 0)
            ;; if this is a repeated undo-in-region, then we've left the current
            ;; node at the original splice-point; we need to set the current
            ;; node to the equivalent node on the undo-in-region branch and redo
            ;; back to where we started
            (when undo-tree--repeated-undo-in-region
              (setf (undo-tree-current undo-tree-list)
              (undo-tree-node-previous original-fragment))
              (let ((mark-active nil))
                (while (not (eq (undo-tree-current undo-tree-list) splice))
                  (undo-tree--undo-or-redo nil 'redo 'preserve-undo nil nil))))
            ;; splice new undo-in-region node into fragment
            (setq node (undo-tree-make-node nil region-changeset nil nil))
            (undo-tree-splice-node node splice)
            ;; set current node to undo-in-region node
            (setf (undo-tree-current undo-tree-list) node)))
          ;; update undo-tree size
        (setq node (undo-tree-node-previous fragment))
        (while (progn
           (and (setq node (car (undo-tree-node-next node)))
                (not (eq node original-fragment))
                (incf (undo-tree-count undo-tree-list))
                (incf (undo-tree-size undo-tree-list)
                        (+ (undo-tree-byte-size (undo-tree-node-undo node))
                           (undo-tree-byte-size (undo-tree-node-redo node)))))))
        (undo-tree-set-timestamp nil 'walk nil)
        t)))) ;; indicate undo-in-region branch was successfully pulled

(defun undo-tree-pull-redo-in-region-branch (start end)
"Pull out entries from redo changesets to create a new redo-in-region
branch, which redoes changeset entries lying between START and END first,
followed by remaining entries from the changesets. Repeated calls will,
if appropriate, extend the current redo-in-region branch rather than
creating a new one.
If we're just reverting the last undo-in-region, we don't need to
manipulate the undo tree at all."
  (if (undo-tree-reverting-undo-in-region-p start end)
      t  ; return t to indicate success
    ;; We build the `region-changeset' and `delta-list' lists forwards, using
    ;; pointers `r' and `d' to the penultimate element of the list. So that we
    ;; don't have to treat the first element differently, we prepend a dummy
    ;; leading nil to the lists, and have the pointers point to that
    ;; initially.
    ;; Note: using '(nil) instead of (list nil) in the `let*' causes bizarre
    ;;       errors when the code is byte-compiled, where parts of the lists
    ;;       appear to survive across different calls to this function.  An
    ;;       obscure byte-compiler bug, perhaps?
    (let* ((region-changeset (list nil))
           (r region-changeset)
           (delta-list (list nil))
           (d delta-list)
           (node (undo-tree-current undo-tree-list))
           (undo-tree--repeated-redo-in-region
             (undo-tree-repeated-redo-in-region-p start end))
           (undo-tree--new-redo-in-region
             (and (null undo-tree--repeated-redo-in-region)
                  (undo-tree-node-next node)))
           undo-tree-adjusted-markers  ; `undo-elt-in-region' expects this
           fragment splice got-visible-elt redo-list elt)
      ;; --- inisitalisation ---
      (cond
        ;; if this is a repeated redo-in-region, detach fragment below current
        ;; node
        (undo-tree--repeated-redo-in-region
          (when (setq fragment (car (undo-tree-node-next node)))
            (setf (undo-tree-node-previous fragment) nil
            (undo-tree-node-next node)
            (delq fragment (undo-tree-node-next node)))))
               ;; if this is a new redo-in-region, initial fragment is a copy of all
               ;; nodes below the current one in the active branch
        (undo-tree--new-redo-in-region
          (setq fragment (undo-tree-make-node nil nil nil nil)
                splice fragment)
          (while (setq node (nth (undo-tree-node-branch node) (undo-tree-node-next node)))
            (let ((n (undo-tree-make-node
                       splice
                       nil
                       (undo-copy-list (undo-tree-node-redo node))
                       nil)))
              (push n (undo-tree-node-next splice)))
            (setq splice (car (undo-tree-node-next splice))))
          (setq fragment (car (undo-tree-node-next fragment)))))
      ;; --- pull redo-in-region elements into branch ---
      ;; work down fragment, pulling out redo elements within region until
      ;; we've got one that redoes a visible change (insertion or deletion)
      (setq node fragment)
      (catch 'abort
        (while (and (not got-visible-elt) node (undo-tree-node-redo node))
          ;; we cons a dummy nil element on the front of the changeset so that
          ;; we can conveniently remove the first (real) element from the
          ;; changeset if we need to; the leading nil is removed once we're
          ;; done with this changeset
          (setq redo-list (push nil (undo-tree-node-redo node))
                elt (cadr redo-list))
          (while elt
            (cond
              ;; keep elements within region
              ((undo-elt-in-region elt start end)
                ;; set flag if kept element is visible (insertion or deletion)
                (when (and (consp elt)
                           (or (stringp (car elt)) (integerp (car elt))))
                  (setq got-visible-elt t))
                ;; adjust buffer positions in elements previously redone before
                ;; kept element, as kept element will now be redone first
                (undo-tree-adjust-elements-to-elt fragment elt t)
                ;; move kept element to redo-in-region changeset, adjusting its
                ;; buffer position as it will now be redone first
                (setcdr r (list (undo-tree-apply-deltas elt (cdr delta-list) -1)))
                (setq r (cdr r))
                (setcdr redo-list (cddr redo-list)))
              ;; discard "was unmodified" elements
              ;; FIXME: deal properly with these
              ((and (consp elt) (eq (car elt) t))
                (setcdr redo-list (cddr redo-list)))
              ;; if element crosses region, we can't pull any more elements
              ((undo-elt-crosses-region elt start end)
                ;; if we've found a visible element, it must be earlier in
                ;; current node's changeset; stop pulling elements (null
                ;; `redo-list' and non-nil `got-visible-elt' cause loop to exit)
                (if got-visible-elt
                  (setq redo-list nil)
                  ;; if we haven't found a visible element yet, pulling
                  ;; redo-in-region branch has failed
                  (setq region-changeset nil)
                  (throw 'abort t)))
              ;; if rejecting element, add its delta (if any) to the list
              (t
                (let ((delta (undo-delta elt)))
                  (when (/= 0 (cdr delta))
                    (setcdr d (list delta))
                    (setq d (cdr d))))
                (setq redo-list (cdr redo-list))))
            ;; process next element of current changeset
            (setq elt (cadr redo-list)))
          ;; if there are remaining elements in changeset, remove dummy nil
          ;; from front
          (if (cadr (undo-tree-node-redo node))
            (pop (undo-tree-node-undo node))
            ;; otherwise, if we've kept all elements in changeset, discard
            ;; empty changeset
            (if (eq fragment node)
              (setq fragment (car (undo-tree-node-next fragment)))
              (undo-tree-snip-node node)))
          ;; process changeset from next node in fragment
          (setq node (car (undo-tree-node-next node))))) ;;; END `catch' / `while' loop.
      ;; pop dummy nil from front of `region-changeset'
      (setq region-changeset (cdr region-changeset))
      ;; --- integrate branch into tree ---
      (setq node (undo-tree-current undo-tree-list))
      ;; if no redo-in-region elements were found, restore undo tree
      (if (null (car region-changeset))
        (when (and undo-tree--repeated-redo-in-region fragment)
          (push fragment (undo-tree-node-next node))
          (setf (undo-tree-node-branch node) 0
          (undo-tree-node-previous fragment) node)
          nil)  ; return nil to indicate failure
        ;; otherwise, add redo-in-region node to top of fragment, and attach
        ;; it below current node
        (setq fragment
              (if fragment
                (undo-tree-grow-backwards fragment nil region-changeset nil)
                (undo-tree-make-node nil nil region-changeset nil)))
        (push fragment (undo-tree-node-next node))
        (setf (undo-tree-node-branch node) 0
               (undo-tree-node-previous fragment) node)
        ;; update undo-tree size
        (unless undo-tree--repeated-redo-in-region
          (setq node fragment)
          (while (and (setq node (car (undo-tree-node-next node)))
                      (incf (undo-tree-count undo-tree-list))
                      (incf (undo-tree-size undo-tree-list) (undo-tree-byte-size (undo-tree-node-redo node))))))
        (incf (undo-tree-size undo-tree-list) (undo-tree-byte-size (undo-tree-node-redo fragment)))
        (undo-tree-set-timestamp nil 'walk nil)
        t)))) ;; indicate redo-in-region branch was successfully pulled

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; `undo-tree-transfer-list'

(defun undo-tree-transfer-list ()
"Transfer entries accumulated in `buffer-undo-list' to `undo-tree-list'.
`undo-tree-transfer-list' should never be called when undo is disabled;
i.e. `buffer-undo-list' is `t`."
  (cl-assert (not (eq buffer-undo-list t)))
  ;;; Warn the user if the previous `undo-tree-list' will be replaced with
  ;;; the new tree fragment.  https://debbugs.gnu.org/cgi/bugreport.cgi?bug=27214
  ;;; Setting the `undo-limit' to have the same value as `undo-strong-limit' should
  ;;; prevent `truncate_undo_list' in `undo.c' from truncating the `undo-tree-canary'
  ;;; in the `buffer-undo-list' during garbage collection.
  (when (and undo-tree-list
             buffer-undo-list
             (not (memq 'undo-tree-canary buffer-undo-list))
             (not (minibufferp)))
    (display-warning '(undo-tree-transfer-list truncate-info local-variables)
      (format "\n
This warning happens when ALL of the following conditions exist:\n
(1) `undo-tree-list' is non-nil.
(2) `buffer-undo-list' is non-nil.
(3) `undo-tree-canary' is not an `memq' of the `buffer-undo-list'.
(4) The current-buffer is not a minibuffer.\n
The following are some examples where this situation is known to occur:\n
(I) The `undo-tree-canary' in the `bufer-undo-list' of `%s`
may have been truncated by `truncate_undo_list' in `undo.c' during
garbage collection.  Please check to see whether `undo-limit' and
`undo-strong-limit' are set to the same values as described in the
commentary at the outset of this library.\n
(II) Local variables are gathered from a buffer where `undo-tree-mode'
is active by using the function `buffer-local-variables', which excludes
the `buffer-undo-list':  https://emacs.stackexchange.com/q/3725/2287.
A new buffer gets generated and something is done to the buffer which
populates the `buffer-undo-list'.  The local variables are set in the
new buffer with something like:
  (mapc
    (lambda (v)
      (ignore-errors
         (org-set-local (car v) (cdr v))))
    (buffer-local-variables old-buffer))
A few of the `undo-tree` local variables that were gathered with
`buffer-local-variables' will be set in the new buffer.  Thereafter,
`undo-tree-mode' is turned on; e.g., by turning on a major-mode that
in turn triggered `undo-tree-mode'.\n
-  You can disable the popping up of this buffer by adding entries like
\(undo-tree-transfer-list truncate-info) to the user option
`warning-suppress-types', defined in the `warnings' library.\n"
        (current-buffer))
      :warning)
    (unless (y-or-n-p
                    (format "%s:  Do you really want to discard the prior `undo-tree-list'?"
                      (current-buffer)))
      (let ((debug-on-quit nil))
        (signal 'quit '("undo-tree-transfer-list:  You chose to abort.")))))
  ;; if `undo-tree-list' is empty, create initial undo-tree
  (when (null undo-tree-list)
    (when (buffer-base-buffer)
      (display-warning '(undo-tree-transfer-list indirect-buffer)
        (format "\n
(%s) is an indirect buffer of (%s), and the former may not
have an `undo-tree-list'.  This can occur if `undo-tree-mode' had
not been enabled in the base-buffer prior to calling either
`make-indirect-buffer' or `clone-indirect-buffer'.  In addition,
`global-undo-tree-mode' may be off.  If the user wishes to have
indirect/direct buffers sharing the same `buffer-undo-list' and
`undo-tree-list', then please abort and take affirmative steps
to remedy the situation.  Be sure to avoid a situation where the
`buffer-undo-list' is shared between the indirect/direct buffers
and the `undo-tree-list' is not shared, as the `buffer-undo-list'
will be given an `undo-tree-canary' and the undo history in the
direct buffer would thereby be LOST!\n"
          (current-buffer) (buffer-base-buffer))
        :warning)
      (unless (y-or-n-p (format "%s:  Do you want to proceed anyway?" (current-buffer)))
        (let ((debug-on-quit nil))
          ;;; Calling `(undo-tree-mode -1)` will result in a never ending loop.
          (setq undo-tree-mode nil)
          (signal 'quit '("undo-tree-transfer-list:  You chose to abort.")))))
    (message "undo-tree-transfer-list:  Initializing the `undo-tree-list' (%s)." (current-buffer))
    ;; The timestamp of the initial node is set to `00:00:00:00` instead of the `current-time' to
    ;; avoid a rare occurrence where the initial node and current node had the same timestamp.
    (setq undo-tree-list (make-undo-tree (cons '(0 0) t))))
  ;; make sure there's a canary at end of `buffer-undo-list'
  (when (null buffer-undo-list)
    (setq buffer-undo-list '(nil undo-tree-canary)))
  (unless (or (eq (cadr buffer-undo-list) 'undo-tree-canary)
              (eq (car buffer-undo-list) 'undo-tree-canary))
    ;; create new node from first changeset in `buffer-undo-list', save old
    ;; `undo-tree-list' current node, and make new node the current node
    (let* ((time (current-time))
           (node (undo-tree-make-node nil (undo-tree-pop-changeset) nil (cons time t)))
           (splice (undo-tree-current undo-tree-list))
           (size (undo-tree-byte-size (undo-tree-node-undo node)))
           (count 1))
      ;; CURRENT NODE
      (setf (undo-tree-current undo-tree-list) node)
      ;;; REMOVE THE `t` FROM THE PRIOR CURRENT TIMESTAMP.
      (undo-tree-set-timestamp (undo-tree-previous undo-tree-list) 'off nil)
      ;; grow tree fragment backwards using `buffer-undo-list' changesets
      ;;; MIDDLE NODES
      (while (and buffer-undo-list
                  (not (eq (cadr buffer-undo-list) 'undo-tree-canary)))
        (setq time (time-subtract time .01))
        (setq node (undo-tree-grow-backwards node (undo-tree-pop-changeset) nil time))
        (incf size (undo-tree-byte-size (undo-tree-node-undo node)))
        (incf count))
      ;; if no undo history has been discarded from `buffer-undo-list' since
      ;; last transfer, splice new tree fragment onto end of old
      ;; `undo-tree-list' current node
      (if (or (eq (cadr buffer-undo-list) 'undo-tree-canary)
              (eq (car buffer-undo-list) 'undo-tree-canary))
        ;;; INITIAL NODE; or BRANCH-POINT; or just plain old continuation.
        (progn
          (setf (undo-tree-node-previous node) splice)
          ;;; BRANCH-POINT
          ;;; The SPLICE is the current node.  If a next node does not exist,
          ;;; then we are only dealing with a continuation of the same branch.
          (when (undo-tree-node-next splice)
            (undo-tree-set-timestamp (undo-tree-node-previous node) 'new (time-subtract time .01)))
          (push node (undo-tree-node-next splice))
          (setf (undo-tree-node-branch splice) 0)
          (incf (undo-tree-size undo-tree-list) size)
          (incf (undo-tree-count undo-tree-list) count))
        ;;; If undo history has been discarded, replace entire `undo-tree-list' with new tree fragment.
        ;;; WARNING:  An existing `undo-tree-list' will be discarded if the `buffer-undo-list'
        ;;; is non-`nil` with no `undo-tree-canary`.
        ;;; INITIAL NODE
        (setq node (undo-tree-grow-backwards node nil nil (time-subtract time .01)))
        (setf (undo-tree-root undo-tree-list) node)
        (setf (undo-tree-size undo-tree-list) size)
        (setf (undo-tree-count undo-tree-list) count)
        (setq buffer-undo-list '(nil undo-tree-canary))))
    ;; discard undo history if necessary
    (undo-tree-discard-history--one-of-two)
    ;; (undo-tree-discard-history--two-of-two)
    ))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Undo-tree commands

(define-minor-mode undo-tree-mode
  "Toggle undo-tree mode.
With no argument, this command toggles the mode.
A positive prefix argument turns the mode on.
A negative prefix argument turns it off.
-  Undo-tree-mode replaces Emacs' standard undo feature with a more
powerful yet easier to use version, that treats the undo history
as what it is: a tree.
-  The following keys are available in `undo-tree-mode':
-    \\{undo-tree-mode-map}
-  Within the undo-tree visualizer, the following keys are available:
-    \\{undo-tree-visual-mode-map}"
  nil                       ; init value
  undo-tree-mode-lighter    ; lighter
  undo-tree-mode-map        ; keymap
  (if (not (version-list-<= (version-to-list emacs-version) '(25 3 1)))
    (progn
      (setq undo-tree-mode nil)
      (message "undo-tree-mode:  Sorry ... undo-tree is incompatible with > Emacs '(25 3 1)"))
    (let* ((exclusions--major-mode (memq major-mode undo-tree-exclude-modes))
           (exclusions--buffers (undo-tree-regexp-match-p undo-tree-exclude-buffers (buffer-name (current-buffer))))
           (exclusions--files (member buffer-file-name undo-tree-exclude-files))
           (buffer-undo-list--t (eq buffer-undo-list t))
           (minibuffer-p (minibufferp))
           (exclusions--all
             (let (tmp)
               (when exclusions--major-mode
                 (push 'major-mode tmp))
               (when exclusions--buffers
                 (push 'buffers tmp))
               (when exclusions--files
                 (push 'files tmp))
               (when buffer-undo-list--t
                 (push 'undo-disabled tmp))
               (when minibuffer-p
                 (push 'minibuffer tmp))
               tmp)))
      (cond
        ((and undo-tree-mode
              (not buffer-undo-list--t)
              (not minibuffer-p)
              (not exclusions--major-mode)
              (not exclusions--buffers)
              (not exclusions--files))
          (or (and undo-tree-history-autosave
                   buffer-file-name
                   (undo-tree-history-restore nil))
              (undo-tree-transfer-list))
              (add-hook 'write-file-functions 'undo-tree-history-save-hook 'append 'local)
              (add-hook 'change-major-mode-hook 'undo-tree--change-major-mode-fn 'append 'local)
          (when (called-interactively-p 'any)
            (message "Turned ON `undo-tree-mode`.")))
        ((and undo-tree-mode
              (or
                buffer-undo-list--t
                minibuffer-p
                exclusions--major-mode
                exclusions--buffers
                exclusions--files))
          (if (and (called-interactively-p 'any)
                   (not buffer-undo-list--t)
                   (not minibuffer-p)
                   (y-or-n-p (format "`undo-tree-mode`:  Exclusions %s -- enable anyway?" exclusions--all)))
            (progn
              (or (and undo-tree-history-autosave
                       buffer-file-name
                       (undo-tree-history-restore nil))
                  (undo-tree-transfer-list))
              (add-hook 'write-file-functions 'undo-tree-history-save-hook 'append 'local)
              (add-hook 'change-major-mode-hook 'undo-tree--change-major-mode-fn 'append 'local)
              (message "Turned ON `undo-tree-mode` despite exclusions %s." exclusions--all))
          (setq undo-tree-mode nil)
          (message "Turned OFF `undo-tree-mode` due to exclusions %s." exclusions--all)))
        (t
          ;; If disabling `undo-tree-mode', rebuild `buffer-undo-list' from tree so Emacs undo can work.
          (undo-tree-rebuild-undo-list)
          (setq undo-tree-list nil)
          (remove-hook 'write-file-functions 'undo-tree-history-save-hook 'local)
          (remove-hook 'change-major-mode-hook 'undo-tree--change-major-mode-fn 'local)
          (when (called-interactively-p 'any)
            (message "Turned OFF `undo-tree-mode`.")))))))

(defun undo-tree--change-major-mode-fn ()
"Prompt the user to execute `save-buffer' and `undo-tree-history-save'.
If the user says `no`, then a `no harm, no foul` message will appear.
This is only relevant when `undo-tree-history-autosave' has a non-nil value."
  (when undo-tree-history-autosave
    (if (and (buffer-modified-p)
             (y-or-n-p "undo-tree--change-major-mode-fn:  `save-buffer' + `undo-tree-history-save'?"))
      (save-buffer)
      (message "undo-tree--change-major-mode-fn:  The SHA! will not match if `undo-tree-mode' is reenabled -- no harm, no foul."))))

(defun undo-tree--turn-on-undo-tree-mode ()
"Enable `undo-tree-mode' in the current buffer, when appropriate.
-  Some major modes implement their own undo system, which should
not normally be overridden by `undo-tree-mode'. This command does
not enable `undo-tree-mode' in such buffers. If you want to force
`undo-tree-mode' to be enabled regardless, use (undo-tree-mode 1)
instead.
-  The heuristic used to detect major modes in which
`undo-tree-mode' should not be used is to check whether either
the `undo' command has been remapped, or the default undo
keybindings (C-/ and C-_) have been overridden somewhere other
than in the global map. In addition, `undo-tree-mode' will not be
enabled if the buffer's `major-mode' appears in `undo-tree-exclude-modes'."
(interactive)
  (unless (or (key-binding [remap undo])
              (undo-tree-overridden-undo-bindings-p))
    (undo-tree-mode 1)))

(define-globalized-minor-mode global-undo-tree-mode undo-tree-mode undo-tree--turn-on-undo-tree-mode)

(defun undo-tree-overridden-undo-bindings-p ()
"Returns t if default undo bindings are overridden, nil otherwise.
Checks if either of the default undo key bindings (\"C-/\" or
\"C-_\") are overridden in the current buffer by any keymap other
than the global one. (So global redefinitions of the default undo
key bindings do not count.)"
  (let ((binding1 (lookup-key (current-global-map) [?\C-/]))
        (binding2 (lookup-key (current-global-map) [?\C-_])))
    (global-set-key [?\C-/] 'undo)
    (global-set-key [?\C-_] 'undo)
    (unwind-protect
      (or (and (key-binding [?\C-/])
               (not (eq (key-binding [?\C-/]) 'undo)))
          (and (key-binding [?\C-_])
               (not (eq (key-binding [?\C-_]) 'undo))))
      (global-set-key [?\C-/] binding1)
      (global-set-key [?\C-_] binding2))))

(defun undo-tree-switch-branch (branch)
"Switch to a different BRANCH of the undo tree.
This will affect which branch to descend when *redoing* changes
using `undo-tree-classic-redo'."
(interactive (list (or (and prefix-arg
                            (prefix-numeric-value prefix-arg))
                       (and (not (eq buffer-undo-list t))
                            (or (undo-tree-transfer-list) t)
                            (let ((b (undo-tree-node-branch (undo-tree-current undo-tree-list))))
                              (cond
                                ;; switch to other branch if only 2
                                ((= (undo-tree-num-branches) 2)
                                  (- 1 b))
                                ;; prompt if more than 2
                                ((> (undo-tree-num-branches) 2)
                                  (read-number
                                    (format "Branch (0-%d, on %d): " (1- (undo-tree-num-branches)) b)))))))))
  ;; throw error if undo is disabled in buffer
  (when (eq buffer-undo-list t)
    (user-error "undo-tree-switch-branch:  No undo information in this buffer!"))
  ;; sanity check branch number
  (when (<= (undo-tree-num-branches) 1)
    (user-error "Not at undo branch point"))
  (when (or (< branch 0) (> branch (1- (undo-tree-num-branches))))
    (user-error "Invalid branch number"))
  ;; transfer entries accumulated in `buffer-undo-list' to `undo-tree-list'
  (undo-tree-transfer-list)
  ;; switch branch
  (setf (undo-tree-node-branch (undo-tree-current undo-tree-list)) branch)
  (message "Switched to branch %d" branch))

(defun undo-tree-save-state-to-register (register)
"Store current undo-tree state to REGISTER.
The saved state can be restored using
`undo-tree-restore-state-from-register'.
Argument is a character, naming the register."
(interactive "cUndo-tree state to register: ")
  ;; throw error if undo is disabled in buffer
  (when (eq buffer-undo-list t)
    (user-error "undo-tree-save-state-to-register:  No undo information in this buffer!"))
  ;; transfer entries accumulated in `buffer-undo-list' to `undo-tree-list'
  (undo-tree-transfer-list)
  ;; save current node to REGISTER
  (set-register
   register (registerv-make
       (undo-tree-make-register-data
        (current-buffer) (undo-tree-current undo-tree-list))
       :print-func 'undo-tree-register-data-print-func))
  ;; record REGISTER in current node, for visualizer
  (setf (undo-tree-node-register (undo-tree-current undo-tree-list))
  register))

(defun undo-tree-restore-state-from-register (register)
"Restore undo-tree state from REGISTER.
The state must be saved using `undo-tree-save-state-to-register'.
Argument is a character, naming the register."
(interactive "*cRestore undo-tree state from register: ")
  ;; throw error if undo is disabled in buffer, or if register doesn't contain
  ;; an undo-tree node
  (let ((data (registerv-data (get-register register))))
    (cond
     ((eq buffer-undo-list t)
      (user-error "undo-tree-restore-state-from-register:  No undo information in this buffer!"))
     ((not (undo-tree-register-data-p data))
      (user-error "Register doesn't contain undo-tree state"))
     ((not (eq (current-buffer) (undo-tree-register-data-buffer data)))
      (user-error "Register contains undo-tree state for a different buffer")))
    ;; transfer entries accumulated in `buffer-undo-list' to `undo-tree-list'
    (undo-tree-transfer-list)
    ;; restore buffer state corresponding to saved node
    (undo-tree-set (undo-tree-register-data-node data))))

(defun undo-tree--undo-or-redo (arg &optional undo-or-redo preserve-undo-or-redo preserve-timestamps target-timestamp)
"Internal undo function. An active mark in `transient-mark-mode', or
non-nil ARG otherwise, enables undo-in-region. Non-nil PRESERVE-REDO
causes the existing redo record to be preserved, rather than replacing it
with the new one generated by undoing. Non-nil PRESERVE-TIMESTAMPS
disables updating of timestamps in visited undo-tree nodes.  This latter
should *only* be used when temporarily visiting another undo state and
immediately returning to the original state afterwards. Otherwise, it
could cause history-discarding errors."
  (let ((undo-in-progress t)
        (undo-in-region
          (and undo-tree-enable-undo-in-region
               (or (region-active-p)
                   (and arg (not (numberp arg))))))
        (redo-in-region (and undo-tree-enable-undo-in-region
                             (or (region-active-p)
                                 (and arg (not (numberp arg))))))
        (reset-timestamp-fn
          (lambda ()
            ;;; `undo-tree-visual-classic-undo' does not pre-select a particular timestamp, so we use the most recent.
            (let* ((current-node (undo-tree-current undo-tree-list))
                   (timestamps (undo-tree-node-history current-node))
                   (target-timestamp
                     (cond
                       (target-timestamp)
                       ((> (length (undo-tree-node-next current-node)) 1)
                         (let* ((position (undo-tree-node-branch current-node))
                                (ts (nth position timestamps)))
                           (car ts)))
                       (t
                         (caar timestamps)))))
              (undo-tree-set-timestamp (undo-tree-previous undo-tree-list) 'off nil)
              (undo-tree-set-timestamp nil 'on target-timestamp))))
        pos current)
    ;; transfer entries accumulated in `buffer-undo-list' to `undo-tree-list'
    (undo-tree-transfer-list)
    (dotimes (i (or (and (numberp arg) (prefix-numeric-value arg)) 1))
      (cond
        ((eq undo-or-redo 'undo)
          ;; check if at top of undo tree
          (unless (undo-tree-node-previous (undo-tree-current undo-tree-list))
            (user-error "undo-tree--undo-or-redo:  No further undo information."))
          ;; if region is active, or a non-numeric prefix argument was supplied,
          ;; try to pull out a new branch of changes affecting the region
          (when (and undo-in-region
                     (not (undo-tree-pull-undo-in-region-branch (region-beginning) (region-end))))
            (user-error "undo-tree--undo-or-redo:  No further undo information for region."))
          ;; remove any GC'd elements from node's undo list
          (setq current (undo-tree-current undo-tree-list))
          (decf (undo-tree-size undo-tree-list) (undo-tree-byte-size (undo-tree-node-undo current)))
          (setf (undo-tree-node-undo current) (undo-tree-clean-GCd-elts (undo-tree-node-undo current)))
          (incf (undo-tree-size undo-tree-list) (undo-tree-byte-size (undo-tree-node-undo current)))
          ;; undo one record from undo tree
          (when undo-in-region
            (setq pos (set-marker (make-marker) (point)))
            (set-marker-insertion-type pos t))
          (undo-tree--primitive-undo 1 (undo-tree-copy-list (undo-tree-node-undo current)))
          (undo-boundary)
          ;; if preserving old redo record, discard new redo entries that
          ;; `undo-tree--primitive-undo' has added to `buffer-undo-list', and remove any GC'd
          ;; elements from node's redo list
          (if preserve-undo-or-redo
            (progn
              (undo-tree-pop-changeset)
              (decf (undo-tree-size undo-tree-list) (undo-tree-byte-size (undo-tree-node-redo current)))
              (setf (undo-tree-node-redo current) (undo-tree-clean-GCd-elts (undo-tree-node-redo current)))
              (incf (undo-tree-size undo-tree-list) (undo-tree-byte-size (undo-tree-node-redo current))))
            ;; otherwise, record redo entries that `undo-tree--primitive-undo' has added to
            ;; `buffer-undo-list' in current node's redo record, replacing
            ;; existing entry if one already exists
            (decf (undo-tree-size undo-tree-list) (undo-tree-byte-size (undo-tree-node-redo current)))
            (setf (undo-tree-node-redo current) (undo-tree-pop-changeset 'discard-pos))
            (incf (undo-tree-size undo-tree-list) (undo-tree-byte-size (undo-tree-node-redo current))))
          ;; rewind current node and update timestamp
          (setf (undo-tree-current undo-tree-list) (undo-tree-node-previous (undo-tree-current undo-tree-list)))
          (unless preserve-timestamps
            (setf (undo-tree-node-timestamp (undo-tree-current undo-tree-list)) (current-time)))
          ;; if undoing-in-region, record current node, region and direction so we
          ;; can tell if undo-in-region is repeated, and re-activate mark if in
          ;; `transient-mark-mode'; if not, erase any leftover data
          (if (not undo-in-region)
            (undo-tree-node-clear-region-data current)
            (goto-char pos)
            ;; note: we deliberately want to store the region information in the
            ;; node *below* the now current one
            (setf (undo-tree-node-undo-beginning current) (region-beginning)
                   (undo-tree-node-undo-end current) (region-end))
            (set-marker pos nil)))
        ((eq undo-or-redo 'redo)
          ;; check if at bottom of undo tree
          (when (null (undo-tree-node-next (undo-tree-current undo-tree-list)))
            (user-error "undo-tree--undo-or-redo:  No further redo information."))
          ;; if region is active, or a non-numeric prefix argument was supplied,
          ;; try to pull out a new branch of changes affecting the region
          (when (and redo-in-region
                     (not (undo-tree-pull-redo-in-region-branch (region-beginning) (region-end))))
            (user-error "undo-tree--undo-or-redo:  No further redo information for region."))
          ;; get next node (but DON'T advance current node in tree yet, in case
          ;; redoing fails)
          (setq current (undo-tree-current undo-tree-list)
                current (nth (undo-tree-node-branch current) (undo-tree-node-next current)))
          ;; remove any GC'd elements from node's redo list
          (decf (undo-tree-size undo-tree-list) (undo-tree-byte-size (undo-tree-node-redo current)))
          (setf (undo-tree-node-redo current) (undo-tree-clean-GCd-elts (undo-tree-node-redo current)))
          (incf (undo-tree-size undo-tree-list) (undo-tree-byte-size (undo-tree-node-redo current)))
          ;; redo one record from undo tree
          (when redo-in-region
            (setq pos (set-marker (make-marker) (point)))
            (set-marker-insertion-type pos t))
          (undo-tree--primitive-undo 1 (undo-tree-copy-list (undo-tree-node-redo current)))
          (undo-boundary)
          ;; advance current node in tree
          (setf (undo-tree-current undo-tree-list) current)
          ;; if preserving old undo record, discard new undo entries that
          ;; `undo-tree--primitive-undo' has added to `buffer-undo-list', and remove any GC'd
          ;; elements from node's redo list
          (if preserve-undo-or-redo
            (progn
              (undo-tree-pop-changeset)
              (decf (undo-tree-size undo-tree-list) (undo-tree-byte-size (undo-tree-node-undo current)))
              (setf (undo-tree-node-undo current) (undo-tree-clean-GCd-elts (undo-tree-node-undo current)))
              (incf (undo-tree-size undo-tree-list) (undo-tree-byte-size (undo-tree-node-undo current))))
            ;; otherwise, record undo entries that `undo-tree--primitive-undo' has added to
            ;; `buffer-undo-list' in current node's undo record, replacing
            ;; existing entry if one already exists
            (decf (undo-tree-size undo-tree-list) (undo-tree-byte-size (undo-tree-node-undo current)))
            (setf (undo-tree-node-undo current) (undo-tree-pop-changeset 'discard-pos))
            (incf (undo-tree-size undo-tree-list) (undo-tree-byte-size (undo-tree-node-undo current))))
          ;; update timestamp
          (unless preserve-timestamps
            (setf (undo-tree-node-timestamp current) (current-time)))
          ;; if redoing-in-region, record current node, region and direction so we
          ;; can tell if redo-in-region is repeated, and re-activate mark if in
          ;; `transient-mark-mode'
          (if (not redo-in-region)
            (undo-tree-node-clear-region-data current)
            (goto-char pos)
            (setf (undo-tree-node-redo-beginning current) (region-beginning)
                   (undo-tree-node-redo-end current) (region-end))
            (set-marker pos nil)))))
    (cond
      ((eq undo-or-redo 'undo)
        ;; undo deactivates mark unless undoing-in-region
        (setq deactivate-mark (not undo-in-region)))
      ((eq undo-or-redo 'redo)
        ;; redo deactivates the mark unless redoing-in-region
        (setq deactivate-mark (not redo-in-region))))
    (funcall reset-timestamp-fn)))

(defun undo-tree-classic-undo (arg)
"Undo changes.  Repeat this command to undo more changes.
A numeric ARG serves as a repeat count.
In Transient Mark mode when the mark is active, only undo changes
within the current region. Similarly, when not in Transient Mark
mode, just \\[universal-argument] as an argument limits undo to
changes within the current region."
(interactive "P")
  (when buffer-read-only
    (let ((debug-on-quit nil))
      (signal 'quit '("undo-tree-classic-undo:  Buffer is read-only!"))))
  (undo-tree--undo-or-redo arg 'undo nil nil nil)
  (undo-tree-announce-branch-point "undo-tree-classic-undo"))

(defun undo-tree-classic-redo (arg)
"Redo changes. A numeric ARG serves as a repeat count.
In Transient Mark mode when the mark is active, only redo changes
within the current region. Similarly, when not in Transient Mark
mode, just \\[universal-argument] as an argument limits redo to
changes within the current region."
(interactive "P")
  (when buffer-read-only
    (let ((debug-on-quit nil))
      (signal 'quit '("undo-tree-classic-redo:  Buffer is read-only!"))))
  (undo-tree--undo-or-redo arg 'redo nil nil nil)
  (undo-tree-announce-branch-point "undo-tree-classic-redo"))

(defun undo-tree--find-node (timestamp n)
"Go to the desired node commencing from an existing TIME-STAMP in LIST.
If N is positive, then go forwards in time by that number of N time-stamps.
If N is negative, then backwards in time by that number of N time-stamps.
If node does not exist, return nil; otherwise, return node and corresponding time-stamp."
  (when (eq buffer-undo-list t)
    (user-error "undo-tree-got-node:  No undo information in this buffer!"))
  (let* ((timestamp (time-to-seconds timestamp))
         (master-list
           (let* ((beginning-node (undo-tree-root undo-tree-list))
                  (stack (list beginning-node))
                  n res)
             (while stack
               (setq n (pop stack))
               (push n res)
               (setq stack (append (undo-tree-node-next n) stack)))
             res))
         (the-list
           (mapcar
             (lambda (node)
               (let* ((linear-history (undo-tree-node-history node))
                      (history--seconds+normal
                        (mapcar
                          (lambda (ts)
                            (let ((car-ts (car ts))
                                  (cdr-ts (cdr ts)))
                              (list (list (time-to-seconds car-ts) car-ts) cdr-ts)))
                          linear-history)))
                 (list node history--seconds+normal)))
             master-list)))
    ;;; DEBUGGING:
    ;;;   (message "the-list: %s" the-list)
    (tobias--goto-node the-list timestamp n)))

;;; Generate a complete (rassoc-) map assigning time-stamps to nodes at first.
;;; Afterwards sort and then locate time-stamp in the sorted list.
;;; From there you can go forward and backward.
;;;
;;; EXAMPLES:  The asterisk represents a standard timestamp list format.
;;  (setq l '(([node1] (((5.6 *)) ((3.7 *)) ((11.7 *)) ((8.2 *))))
;;            ([node2] (((4.4 *)) ((9.9 *)) ((6.1 *) . t)))
;;            ([node3] (((7.5 *)) ((2.3 *)) ((1.5 *))))
;;            ([node4] (((10.3 *))))))
;;  (tobias--goto-node l 5.6 1) ; => ([node2] ((6.1 *) . t))
;;  (tobias--goto-node l 6.1 -1) ; => '([node3] ((5.6 *)))
;;  (tobias--goto-node l 6.1 -4) ; => '([node3] ((2.3 *)))
;;  (tobias--goto-node l 6.1 1) ; => '([node3] ((7.5 *)))
;;  (tobias--goto-node l 6.1 4) ; => '([node4] ((10.3 *)))
;;  (tobias--goto-node l 6.1 5) ; => '([node1] ((11.7 *)))
;;  (tobias--goto-node l 6.1 6) ; => '([node1] ((11.7 *)))
;;  (tobias--goto-node l 6.1 7) ; => '([node1] ((11.7 *)))
(defun tobias--goto-node (list time-stamp n)
"Written by @Tobias:  https://emacs.stackexchange.com/a/32415/2287
Go to the desired node commencing from an existing TIME-STAMP in LIST.
If N is positive, then go forwards in time by that number of N time-stamps.
If N is negative, then backwards in time by that number of N time-stamps.
If node does not exist, return nil; otherwise, return node and corresponding time-stamp."
  (let* ((full-list (apply #'append
                           (loop for node-stamps in list
                                 collect (mapcar (lambda (stamp) (list (car node-stamps) stamp)) (cadr node-stamps)))))
         (full-list (cl-sort full-list (lambda (node-stamp1 node-stamp2) (< (car (caadr node-stamp1)) (car (caadr node-stamp2))))))
         (current-pos (cl-position-if (lambda (node-stamp) (< (abs (- (car (caadr node-stamp)) time-stamp)) 1e-6)) full-list)))
    (assert current-pos nil "Current position/timestamp not found in list!")
    (nth (max (min (+ current-pos n) (1- (length full-list))) 0) full-list)))

(defun undo-tree-set-timestamp (node action time)
"NODE is optional; if `nil`, then use current node.
If ACTION is `eq' TO 'walk, then go down to the leaf and place timstamps
on each node as we walk up the branch to the first branch-point.
If ACTION is `eq' to 'new, then generate and set current timestamp to `t`.
If ACTION is `eq' to 'on, then add `t`.
If ACTION is `eq' to 'off, then remove `t`.
TIME is the timestamp."
  (let ((current-node (undo-tree-current undo-tree-list)))
    ;;; DEBUGGING
    ;;    (message "node: %s | action: %s | time: %s" (length node) action time)
    (cond
      ((eq action 'walk)
        ;;; When chaining undo/redo in tests, the time differential between calls
        ;;; was insufficient to correctly keep things in chronological order.
        ;; (sleep-for .1)
        (let ((n (undo-tree-current undo-tree-list))
              (variable-time (current-time))
              (first-loop t))
          ;;; Go down to the leaf of the active branch.  The leaf will have a
          ;;; `nil` value for `undo-tree-node-next'.
          (while (not (null (undo-tree-node-next n)))
            (setq n (nth (undo-tree-node-branch n) (undo-tree-node-next n))))
          (catch 'done
            (while t
              (if first-loop
                 (setq first-loop nil)
                 (setq variable-time (time-subtract variable-time .01)))
              (let* ((old--linear-history (undo-tree-node-history n))
                     (new--linear-history (push (cons variable-time nil) old--linear-history)))
                (setf (undo-tree-node-history n) new--linear-history))
              (when (and (undo-tree-node-next n) (> (length (undo-tree-node-next n)) 1))
                (throw 'done nil))
              (setq n (undo-tree-node-previous n))))))
      ((eq action 'on)
        (let* ((old--linear-history (undo-tree-node-history (or node current-node)))
               (new--linear-history
                 (mapcar
                   (lambda (ts)
                     (let ((car-ts (car ts))
                           (cdr-ts (cdr ts)))
                       (if (equal car-ts time)
                         (cons car-ts t)
                         (cons car-ts nil))))
                   old--linear-history)))
          ;;; DEBUGGING
          ;;;   (message "time: %s / %s | old: %s | new: %s"
          ;;;     time (format-time-string "%H:%M:%S:%2N" time) old--linear-history new--linear-history)
          (setf (undo-tree-node-history (or node current-node)) new--linear-history)))
      ((eq action 'new)
        (let* ((old--linear-history (undo-tree-node-history (or node current-node)))
               (new--linear-history (push (cons (or time (current-time)) nil) old--linear-history)))
          (setf (undo-tree-node-history (or node current-node)) new--linear-history)))
      ((eq action 'off)
        (let* ((old--linear-history (undo-tree-node-history (or node current-node)))
               (new--linear-history
                 (mapcar
                   (lambda (ts)
                     (let ((car-ts (car ts))
                           (cdr-ts (cdr ts)))
                       (cons car-ts nil)))
                   old--linear-history)))
          (setf (undo-tree-node-history (or node current-node)) new--linear-history)
          (setf (undo-tree-previous undo-tree-list) (undo-tree-current undo-tree-list))))
      (t
        (error "undo-tree-set-timestamp:  situation not contemplated.")))))

(defun undo-tree-set (node &optional preserve-timestamps target-timestamp)
"Set buffer to state corresponding to NODE. Returns intersection point
between path back from current node and path back from selected NODE.
Non-nil PRESERVE-TIMESTAMPS disables updating of timestamps in visited
undo-tree nodes.  This should *only* be used when temporarily visiting
another undo state and immediately returning to the original state
afterwards. Otherwise, it could cause history-discarding errors."
  (let ((path (make-hash-table :test 'eq))
        (n node))
    (puthash (undo-tree-root undo-tree-list) t path)
    ;; build list of nodes leading back from selected node to root, updating
    ;; branches as we go to point down to selected node
    (while (progn
             (puthash n t path)
             (when (undo-tree-node-previous n)
               (setf (undo-tree-node-branch (undo-tree-node-previous n))
                      (undo-tree-position n (undo-tree-node-next (undo-tree-node-previous n))))
               (setq n (undo-tree-node-previous n)))))
    ;; work backwards from current node until we intersect path back from
    ;; selected node
    (setq n (undo-tree-current undo-tree-list))
    (while (not (gethash n path))
      (setq n (undo-tree-node-previous n)))
    ;;; undo/redo will not be triggered if selecting a different timestamp on the same node,
    ;;; so we must reset the active marker of the target-timestamp.  Normally this would have
    ;;; been handled at the tail end of the undo/redo function below.  This is really only
    ;;; needed when swapping branch-point timestamps.
    (when (and (null preserve-timestamps) ;; selection mode when diffing nodes
               (eq (undo-tree-current undo-tree-list) n)
               (eq (undo-tree-current undo-tree-list) node))
      (undo-tree-set-timestamp nil 'on target-timestamp)
      (message "undo-tree-set:  Selecting the same node."))
    ;; ascend tree until intersection node
    (while (not (eq (undo-tree-current undo-tree-list) n))
      (undo-tree--undo-or-redo nil 'undo nil preserve-timestamps target-timestamp))
    ;; descend tree until selected node
    (while (not (eq (undo-tree-current undo-tree-list) node))
      (undo-tree--undo-or-redo nil 'redo nil preserve-timestamps target-timestamp))
    ;;; When diffing nodes, PRESERVE-TIMESTAMPS is `t`.  This next section is used only
    ;;; when using the mouse to select a timestamp on a branch-point node.
    (when (and (> (undo-tree-num-branches) 1) (null preserve-timestamps))
      (let* ((node (undo-tree-current undo-tree-list))
             target-timestamp
             (history
               (mapcar
                 (lambda (x)
                   (when (eq (cdr x) t)
                     (setq target-timestamp (car x)))
                   (car x))
                 (undo-tree-node-history node)))
             (pos (cl-position target-timestamp history)))
        (setf (undo-tree-node-branch node) pos)))
    n))  ; return intersection node

(defun undo-tree-linear--undo-or-redo (arg)
(interactive "P")
  (when (eq buffer-undo-list t)
    (user-error "undo-tree-linear--undo-or-redo:  No undo information in this buffer!"))
  (let* ((dummy (undo-tree-transfer-list))
         (current-node (undo-tree-current undo-tree-list))
         (linear-history (undo-tree-node-history current-node))
         (active-timestamp
           (let (res)
             (catch 'done
               (mapc
                 (lambda (ts)
                   (let ((car-ts (car ts))
                         (cdr-ts (cdr ts)))
                     (when (eq cdr-ts t)
                       (setq res car-ts)
                       (throw 'done nil))))
                 linear-history))
             (if res
               res
              (let ((debug-on-quit nil))
                (signal 'quit '("undo-tree-linear--undo-or-redo:  Cannot locate current timestamp!"))))))
        (target-node+timestamp (undo-tree--find-node active-timestamp arg))
        (target-node (car target-node+timestamp))
        (target-timestamp (cadr (caadr target-node+timestamp))))
        ;;; DEBUGGING
        ;; (message "target-timestamp: %s | active-timestamp: %s | %s"
        ;;   target-timestamp active-timestamp (format-time-string "%H:%M:%S:%2N" active-timestamp))
    (if (and (equal active-timestamp target-timestamp) (eq current-node target-node))
      (cond
        ((and arg (> arg 0))
          (user-error "undo-tree-linerar--undo-or-redo:  No further redo information."))
        ((and arg (< arg 0))
          (user-error "undo-tree-linerar--undo-or-redo:  No further undo information.")))
      (when target-node
        ;;; I want to be able to navigate nodes with multiple timestamps!
        (if (eq current-node target-node)
          (progn
            (undo-tree-set-timestamp (undo-tree-previous undo-tree-list) 'off nil)
            (undo-tree-set-timestamp nil 'on target-timestamp))
          (undo-tree-set target-node nil target-timestamp))))))

(defun undo-tree-linear-undo (arg)
"Undo changes.  Repeat this command to undo more changes.
A numeric ARG serves as a repeat count.
In Transient Mark mode when the mark is active, only undo changes
within the current region. Similarly, when not in Transient Mark
mode, just \\[universal-argument] as an argument limits undo to
changes within the current region."
(interactive "P")
  (when buffer-read-only
    (let ((debug-on-quit nil))
      (signal 'quit '("undo-tree-linear-undo:  Buffer is read-only!"))))
  (if (and undo-tree-enable-undo-in-region
           (region-active-p)
           (or (y-or-n-p "Do you want to undo in region?")
               (deactivate-mark)))
    (undo-tree--undo-or-redo arg 'undo nil nil nil)
    (undo-tree-linear--undo-or-redo (or arg -1)))
  (undo-tree-announce-branch-point "undo-tree-linear-undo"))

(defun undo-tree-linear-redo (arg)
"Redo changes. A numeric ARG serves as a repeat count.
In Transient Mark mode when the mark is active, only redo changes
within the current region. Similarly, when not in Transient Mark
mode, just \\[universal-argument] as an argument limits redo to
changes within the current region."
(interactive "P")
  (when buffer-read-only
    (let ((debug-on-quit nil))
      (signal 'quit '("undo-tree-linear-redo:  Buffer is read-only!"))))
  (if (and undo-tree-enable-undo-in-region
           (region-active-p)
           (or (y-or-n-p "Do you want to redo in region?")
               (deactivate-mark)))
    (undo-tree--undo-or-redo arg 'redo nil nil nil)
    (undo-tree-linear--undo-or-redo (or arg 1)))
  (undo-tree-announce-branch-point "undo-tree-linear-redo"))

(defun undo-tree-announce-branch-point (generated-by)
  (cond
    ((> (undo-tree-num-branches) 1)
      (let* ((node (undo-tree-current undo-tree-list))
             (unmodified (undo-tree-node-unmodified-p node))
             target-timestamp
             (master-history (undo-tree-node-history node))
             (history
               (mapcar
                 (lambda (x)
                   (when (eq (cdr x) t)
                     (setq target-timestamp (car x)))
                   (car x))
                 master-history))
             (pos (cl-position target-timestamp history))
             (human-readable
               (mapcar
                 (lambda (x)
                   (if (eq (cdr x) t)
                     (concat "[nth " (number-to-string pos) " " (format-time-string "%H:%M:%S:%2N" (car x) t) "]")
                     (format-time-string "%H.%M.%S.%2N" (car x) t)))
                 master-history)))
        (message "%s:  %sbranch point %s"
                 generated-by
                 (if unmodified
                   "node unmodified | "
                   "")
                 human-readable)))
    ((undo-tree-node-unmodified-p (undo-tree-current undo-tree-list))
      (message "%s:  current node is unmodified." generated-by))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Persistent storage functions

(defun undo-tree-history-classic-filename (file)
"Create the undo history file name for FILE.
Normally this is the file's name with \".\" prepended and
\".~undo-tree~\" appended.
-  A match for FILE is sought in `undo-tree-history-alist'
\(see the documentation of that variable for details\). If the
directory for the backup doesn't exist, it is created."
  (let* ((backup-directory-alist undo-tree-history-alist)
         (name (make-backup-file-name-1 file))
         (file-name-directory-name (file-name-directory name))
         (file-name-nondirectory-name (file-name-nondirectory name)))
    (concat
      file-name-directory-name
      ;;; If we are already dealing with a hidden file with a leading dot,
      ;;; then do not add an extra dot.
      (if (eq ?\. (aref file-name-nondirectory-name 0))
        ""
        ".")
      file-name-nondirectory-name
      ".~undo-tree~")))

;;; Code is copied from `image-dired.el'.
(defun undo-tree-history-filename (file)
"Return undo-tree history file name for FILE.
Depending on the value of `undo-tree-history-storage', the file
name will vary.  For central undo-tree history file storage, make a
MD5-hash of the history file's directory name and add that to make
the undo-tree history file name unique.  For local storage, just
add a subdirectory.  For standard storage, produce the file name
according to the General Standard."
  (cond
    ((eq 'classic undo-tree-history-storage)
      (undo-tree-history-classic-filename file))
    ((eq 'home undo-tree-history-storage)
     (expand-file-name
      (concat "~/.undo-tree/"
              (md5 (concat "file://" (expand-file-name file)))
              ".~undo-tree~")))
    ((eq 'central undo-tree-history-storage)
     (let* ((f (expand-file-name file))
            (ext (file-name-extension f))
            (md5-hash
              (md5 (file-name-as-directory (file-name-directory f))))
            ;;; Code is copied from `image-dired.el'.
            (undo-tree-history-locate-directory
              (lambda ()
                "Return the current undo-tree history directory (from variable `undo-tree-history-directory').
                Create the undo-tree history directory if it does not exist."
                (let ((undo-tree-history-directory (file-name-as-directory
                                  (expand-file-name undo-tree-history-directory))))
                  (unless (file-directory-p undo-tree-history-directory)
                    (make-directory undo-tree-history-directory t)
                    (message "Creating undo-tree history directory"))
                  undo-tree-history-directory))))
       (format "%s%s%s%s.%s"
               (file-name-as-directory (expand-file-name (funcall undo-tree-history-locate-directory)))
               (file-name-base f)
               (if ext
                 (concat "." ext)
                 "")
               (if md5-hash (concat "_" md5-hash) "")
               "~undo-tree~")))
    ((eq 'local undo-tree-history-storage)
     (let* ((f (expand-file-name file))
            (ext (file-name-extension f)))
       (format "%s.undo-tree/%s%s.%s"
               (file-name-directory f)
               (file-name-base f)
               (if ext
                 (concat "." ext)
                 "")
               "~undo-tree~")))))

;;; Use `symbol-function' to inspect the value.
;;; `tobias--copy-tree*-stack'
;;; `tobias--copy-tree*-stack-new'
;;; `tobias--copy-tree*-hash'
;;; Written by @Tobias:  https://emacs.stackexchange.com/a/32230/2287
(cl-defstruct (tobias--copy-tree*
               (:constructor tobias--copy-tree*-mem
                             (&optional stack stack-new (hash (make-hash-table)))))
  stack stack-new hash)

(defmacro tobias--copy-tree*--push (el el-new mem &optional hash)
"Written by @Tobias:  https://emacs.stackexchange.com/a/32230/2287"
  (let ((my-el (make-symbol "my-el"))
        ;; makes sure `el' is only evaluated once
        (my-el-new (make-symbol "my-el-new")))
    (append `(let ((,my-el ,el)
                   (,my-el-new ,el-new))
               (push ,my-el (tobias--copy-tree*-stack ,mem))
               (push ,my-el-new (tobias--copy-tree*-stack-new ,mem)))
            (and hash
                 `((puthash ,my-el ,my-el-new (tobias--copy-tree*-hash ,mem))))
            (list my-el-new))))

(defmacro tobias--copy-tree*--pop (el el-new mem)
"Written by @Tobias:  https://emacs.stackexchange.com/a/32230/2287"
  `(setq ,el (pop (tobias--copy-tree*-stack ,mem))
         ,el-new (pop (tobias--copy-tree*-stack-new mem))))

(defun tobias--copy-tree*--copy-node (node mem vecp)
"Written by @Tobias:  https://emacs.stackexchange.com/a/32230/2287"
  (if (or (consp node)
      (and vecp (vectorp node)))
      (let ((existing-node (gethash node (tobias--copy-tree*-hash mem))))
    (if existing-node
        existing-node
      (tobias--copy-tree*--push node (if (consp node)
                     (cons nil nil)
                   (make-vector (length node) nil))
                mem t)))
    node))

(defun tobias--copy-tree* (tree &optional vecp)
"Written by @Tobias:  https://emacs.stackexchange.com/a/32230/2287"
  (if (or (consp tree)
      (and vecp (vectorp tree)))
      (let* ((tree-new (if (consp tree) (cons nil nil)
             (make-vector (length tree) nil)))
             (mem (tobias--copy-tree*-mem))
             next
             next-new)
        (tobias--copy-tree*--push tree tree-new mem t)
        (while (tobias--copy-tree*--pop next next-new mem)
          (cond
            ((consp next)
              (setcar next-new (tobias--copy-tree*--copy-node (car next) mem vecp))
              (setcdr next-new (tobias--copy-tree*--copy-node (cdr next) mem vecp)))
            ((and vecp (vectorp next))
              (cl-loop for i from 0 below (length next) do
                (aset next-new i
                  (tobias--copy-tree*--copy-node (aref next i) mem vecp))))))
    tree-new)
    tree))

;;; Copied from `subr.el'.  Some users may be using the `sha1.el' library that is too slow!
(defun undo-tree-sha1 (object &optional start end binary)
"Return the SHA1 (Secure Hash Algorithm) of an OBJECT.
OBJECT is either a string or a buffer.  Optional arguments START and
END are character positions specifying which portion of OBJECT for
computing the hash.  If BINARY is non-nil, return a string in binary
form."
  (secure-hash 'sha1 object start end binary))

(defun undo-tree-history-save (&optional filename overwrite)
"Update and return the `undo-tree-list' as a string or a file.
If FILENAME is omitted, then generate a filename and output to the file.
If FILENAME is a string, then use it as the filename and output to file.
If FILENAME is `t`, then return only a string and do not generate a file.
When saving the history to a file, the optional argument OVERWRITE can be used
to suppress the interactive inquiry about overwriting if the file already exists."
(interactive)
  (unless (eq buffer-undo-list t)
    ;;; If the buffer has been modified and this function has not been called by
    ;;; the `write-file-functions' hook, then offer to save the buffer.
    ;;; When `undo-tree-history-autosave' is non-nil, `undo-tree-history-save'
    ;;; will be triggered when a user saves the buffer by virtue of the
    ;;; `write-file-functions' hook.  In that case, it is necessary to
    ;;; suppress triggering a second call to `save-buffer' herein as it
    ;;; creates a never ending loop asking the user to save the buffer repeatedly.
    (when (and (null undo-tree-history-autosave)
               (buffer-modified-p)
               (y-or-n-p (format "undo-tree-history-save:  %s is modified -- save it now?" (current-buffer))))
      (save-buffer))
    (let* ((original-buffer (current-buffer))
           (hash (undo-tree-sha1 original-buffer))
           (bfn buffer-file-name)
           ;;; Prevent a never ending loop triggered by `write-file' when
           ;;; `undo-tree-history-save' is non-nil and the user saves the buffer, as such
           ;;; action would trigger the `write-file-functions' hook repeatedly.
           (undo-tree-history-autosave nil)
           (filename
             (cond
               ((stringp filename)
                 filename)
               ((null filename)
                 (if buffer-file-name
                   (undo-tree-history-filename buffer-file-name)
                   (expand-file-name (read-file-name "File to save in: ") nil)))))
           tree bfn+hash+tree)
      (when (and filename
                 (file-exists-p filename)
                 (null overwrite))
        (unless (y-or-n-p (format "Overwrite \"%s\"? " filename))
          (let ((debug-on-quit nil)
                (msg (format "undo-tree-history-save -- abort saving: %s" filename)))
            (signal 'quit `(,msg)))))
      ;;; Transfer the tree at the outset before cleaning it just in case the `undo-tree-list'
      ;;; has not yet been created.
      (undo-tree-transfer-list)
      ;;; If visualizer buffer was killed improperly, its data remains in the tree.
      ;;; These leftover entries ... (:visual [0 1 0 #<marker in no buffer>])
      ;;; cause `invalid-read-syntax "#"` when restoring from the history.
      ;;; `yas--snippet-revive' entries also cause `invalid-read-syntax "#"` ...
      ;;;   (apply yas--snippet-revive 15824 15839 #3=[cl-struct-yas--snippet nil nil 6 #<overlay in no buffer> nil nil nil])
      ;;;   (apply yas--take-care-of-redo 15824 15839 #3#)
      (undo-tree-clear-visual-data undo-tree-list)
      (undo-tree-decircle undo-tree-list)
      (setq tree (tobias--copy-tree* undo-tree-list t))
      ;;; Okay to recircle the `undo-tree-list' since we are proceeding with just a copy.
      (undo-tree-recircle undo-tree-list)
      ;;; The hash-table, which is an element of the copy of the `undo-tree-list', is not needed.
      (setf (undo-tree-object-pool tree) nil)
      (let* ((beginning-node (undo-tree-root tree))
             (stack (list beginning-node))
             n y)
        (while stack
          (setq n (pop stack))
          (let ((next-node (undo-tree-node-next n))
                (undo-list (undo-tree-node-undo n))
                (redo-list (undo-tree-node-redo n)))
            (when (drew-adams--true-listp undo-list)
                 (mapc
                   (lambda (x)
                     (cond
                       ;;; This section was written by @PythonNut
                       ;;; https://emacs.stackexchange.com/a/31130/2287
                       ((and (consp x)
                             (stringp (car x)))
                         (setcar x (substring-no-properties (car x))))
                       ;;; This section was written by @Tobias
                       ;;; https://emacs.stackexchange.com/a/32189/2287
                       ((and
                            (setq y x)
                            (consp x)
                            (eq (car x) 'apply)
                            (setq x (cdr x))
                            (consp x)
                            (memq (car x) '(mc/activate-cursor-for-undo
                                            mc/deactivate-cursor-after-undo
                                            yas--take-care-of-redo
                                            yas--snippet-revive)))
                          (setf (undo-tree-node-undo n)
                                 (delete y (undo-tree-node-undo n))))))
                   undo-list))
            (when (drew-adams--true-listp redo-list)
                 (mapc
                   (lambda (x)
                     (cond
                       ;;; This section was written by @PythonNut
                       ;;; https://emacs.stackexchange.com/a/31130/2287
                       ((and (consp x)
                             (stringp (car x)))
                         (setcar x (substring-no-properties (car x))))
                       ;;; This section was written by @Tobias
                       ;;; https://emacs.stackexchange.com/a/32189/2287
                       ((and
                            (setq y x)
                            (consp x)
                            (eq (car x) 'apply)
                            (setq x (cdr x))
                            (consp x)
                            (memq (car x) '(mc/activate-cursor-for-undo
                                            mc/deactivate-cursor-after-undo
                                            yas--take-care-of-redo
                                            yas--snippet-revive)))
                          (setf (undo-tree-node-redo n)
                                 (delete y (undo-tree-node-redo n))))))
                   redo-list))
            (setq stack (append next-node stack)))))
        (let* ((print-circle t)
               ;;; The default values for `print-level' and `print-length' are `nil`,
               ;;; but some users may have customized those variables to be restrictive.
               ;;; We want to avoid "..." abbreviations that can cause errors when
               ;;; restoring the `undo-tree-list':  (wrong-type-argument listp \.\.\.)
               (print-level nil)
               (print-length nil)
               (undo-tree-list--string (prin1-to-string tree)))
          (if (read undo-tree-list--string)
            (setq bfn+hash+tree
                    (concat
                      bfn
                      "\n"
                      hash
                      "\n"
                      undo-tree-list--string))
            (let ((debug-on-quit nil)
                  (error-message
                    (format "undo-tree-history-save:  Error reading back `undo-tree-list':  %s | %s"
                            original-buffer undo-tree-list--string)))
              (signal 'quit `(,error-message)))))
        (when filename
          (with-auto-compression-mode
            (with-temp-file filename
              (insert bfn+hash+tree)))
          (message "undo-tree-history-save:  (%s) %s" original-buffer filename))
      bfn+hash+tree)))

(defun undo-tree-history-restore (&optional string-or-file)
"Load undo-tree history from string or file.  If no argument is passed, then look for a saved
history file in the default location."
(interactive)
  (catch 'sanity-check-error
    (let* ((filename
             (when (null string-or-file)
               (let ((prospective-filename
                      (if buffer-file-name
                        (undo-tree-history-filename buffer-file-name)
                        (expand-file-name (read-file-name "undo-tree-history-restore -- load history file:  ") nil))))
                 (if (file-exists-p prospective-filename)
                   prospective-filename
                   ;;; A friendly-ish message so as not to unnecessarily alarm the user.
                   (message "undo-tree-history-restore:  No history (%s)." buffer-file-name)
                   (throw 'sanity-check-error nil)))))
           (what-is-it (when string-or-file (split-string string-or-file "\n")))
           (original-buffer (current-buffer))
           (sha1-original-buffer (undo-tree-sha1 original-buffer))
           hash tree temp-buffer)
      (with-temp-buffer
        (setq temp-buffer (current-buffer))
        (cond
          ((and string-or-file
                (= 1 (length what-is-it))
                (file-exists-p (car what-is-it)))
            (with-auto-compression-mode
              (insert-file-contents string-or-file)))
          ((and string-or-file
                (not (= 1 (length what-is-it))))
            (insert string-or-file))
          ((null string-or-file)
            (with-auto-compression-mode
              (insert-file-contents filename))))
        ;;; Go to beginning of buffer!
        (goto-char (point-min))
        ;;; Read from `point-min' to end of the slot for the `buffer-file-name'.
        ;;; If reading back the slot for the `buffer-file-name' returns `nil`,
        ;;; then assume this is a history file of a non-file-visiting buffer.
        (unless (read temp-buffer)
          (message "undo-tree-history-restore:  The slot for `buffer-file-name' is empty."))
        ;;; Read from end of the buffer-file-name to the end of the hash string.
        (unless (setq hash (read temp-buffer))
          (message "undo-tree-history-restore:  Error reading saved SHA1 hash:  %s | %s"
                   original-buffer hash)
          (throw 'sanity-check-error nil))
        (unless (string= sha1-original-buffer hash)
          (message "undo-tree-history-restore:  Error comparing current SHA1 to saved SHA1 hash:  %s"
                   original-buffer)
          (throw 'sanity-check-error nil))
        ;;; Read from the end of the hash string to the end of the buffer.
        (unless (setq tree (read temp-buffer))
          (message "undo-tree-history-restore:  Error reading back `undo-tree-list':  %s | %s"
                   original-buffer string-or-file)
          (throw 'sanity-check-error nil)))
      ;; initialise empty undo-tree object pool
      (setf (undo-tree-object-pool tree) (make-hash-table :test 'eq :weakness 'value))
      ;; restore circular undo-tree data structure
      (undo-tree-recircle tree)
      (setq undo-tree-list tree)
      ;;; `undo-tree-mode' tests whether `undo-tree-history-restore' was successful.
      ;;; Technically speaking, the message is a non-nil value, but the `t` is clearer when reading code.
      (cond
        ((null buffer-undo-list)
          (setq buffer-undo-list '(nil undo-tree-canary))
          (message "undo-tree-history-restore:  History restored (%s); `buffer-undo-list' set."
                   original-buffer)
          t)
        ;;; EXAMPLE:  Text properties were added/removed to the buffer, which made their way into the
        ;;;           `buffer-undo-list', however, the sha1 string remains the same before/after.
        ;;;   1.  The `buffer-undo-list' is nil.
        ;;;   2.  (undo-tree-sha1 (current-buffer)) is "12345678abcdefg"
        ;;;   3.  (add-text-properties (line-beginning-position) (line-end-position) '(face (:foreground "blue")))
        ;;;   4.  The `buffer-undo-list' may now have one or more entries.
        ;;;   5.  (undo-tree-sha1 (current-buffer)) is still "12345678abcdefg".
        ;;;   6.  If the `buffer-undo-list' does not have `undo-tree-canary', then `undo-tree-transfer-list'
        ;;;       will ask the user to overwrite the `undo-tree-list'.
        ((and (not (null buffer-undo-list))
                   (not (equal buffer-undo-list '(nil undo-tree-canary))))
          (if (y-or-n-p
                (format "undo-tree-history-restore:  Discard the `buffer-undo-list' (%s)?"
                  original-buffer))
            (progn
              (setq buffer-undo-list '(nil undo-tree-canary))
              (message "undo-tree-history-restore:  History restored (%s); `buffer-undo-list' reset." original-buffer)
              t)
            (let ((debug-on-quit nil))
              (signal 'quit '("undo-tree-history-restore:  Please debug why this happened.")))))
        ;;; Restoring an `undo-tree-list' in a buffer where the `buffer-undo-list' has already been properly set
        ;;; with an `undo-tree-canary'.  There is nothing that needs to be done here.
        (t
          (message "undo-tree-history-restore:  History restored (%s); `buffer-undo-list' previously set."
                   original-buffer)
          t)))))

;; Versions of save/load functions for use in hooks
(defun undo-tree-history-save-hook ()
  (when (and undo-tree-mode undo-tree-history-autosave
             (not (eq buffer-undo-list t))
             (not (memq major-mode undo-tree-exclude-modes))
             (not (undo-tree-regexp-match-p undo-tree-exclude-buffers (buffer-name (current-buffer))))
             (not (member buffer-file-name undo-tree-exclude-files)))
    (undo-tree-history-save nil 'overwrite)
    ;;; The `nil` is important, or else only the history file will be saved but not the current buffer
    ;;; when calling `save-buffer'.
    nil))

(defun undo-tree-history-restore-hook ()
  (when (and undo-tree-mode undo-tree-history-autosave
             (not (eq buffer-undo-list t))
             (not (memq major-mode undo-tree-exclude-modes))
             (not (undo-tree-regexp-match-p undo-tree-exclude-buffers (buffer-name (current-buffer))))
             (not (member buffer-file-name undo-tree-exclude-files))
             (not revert-buffer-in-progress-p))
    (undo-tree-history-restore nil)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Visualizer utility functions

(defun undo-tree-compute-widths (node)
"Recursively compute widths for nodes below NODE."
  (let ((stack (list node))
        res)
    (while stack
      ;; try to compute widths for node at top of stack
      (if (undo-tree-node-p
           (setq res (undo-tree-node-compute-widths (car stack))))
          ;; if computation fails, it returns a node whose widths still need
          ;; computing, which we push onto the stack
          (push res stack)
        ;; otherwise, store widths and remove it from stack
        (setf (undo-tree-node-lwidth (car stack)) (aref res 0)
              (undo-tree-node-cwidth (car stack)) (aref res 1)
              (undo-tree-node-rwidth (car stack)) (aref res 2))
        (pop stack)))))

(defun undo-tree-node-compute-widths (node)
"Compute NODE's left-, centre-, and right-subtree widths.  Returns widths
in the form of a vector if successful. Otherwise, returns a node whose widths need
calculating before NODE's can be calculated."
  (let ((num-children (length (undo-tree-node-next node)))
        (lwidth 0) (cwidth 0) (rwidth 0) p)
    (catch 'need-widths
      (cond
       ;; leaf nodes have 0 width
       ((= 0 num-children)
        (setf cwidth 1
              (undo-tree-node-lwidth node) 0
              (undo-tree-node-cwidth node) 1
              (undo-tree-node-rwidth node) 0))
       ;; odd number of children
       ((= (mod num-children 2) 1)
        (setq p (undo-tree-node-next node))
        ;; compute left-width
        (dotimes (i (/ num-children 2))
          (if (undo-tree-node-lwidth (car p))
              (incf lwidth (+ (undo-tree-node-lwidth (car p))
                              (undo-tree-node-cwidth (car p))
                              (undo-tree-node-rwidth (car p))))
            ;; if child's widths haven't been computed, return that child
            (throw 'need-widths (car p)))
          (setq p (cdr p)))
        (if (undo-tree-node-lwidth (car p))
            (incf lwidth (undo-tree-node-lwidth (car p)))
          (throw 'need-widths (car p)))
        ;; centre-width is inherited from middle child
        (setf cwidth (undo-tree-node-cwidth (car p)))
        ;; compute right-width
        (incf rwidth (undo-tree-node-rwidth (car p)))
        (setq p (cdr p))
        (dotimes (i (/ num-children 2))
          (if (undo-tree-node-lwidth (car p))
              (incf rwidth (+ (undo-tree-node-lwidth (car p))
                              (undo-tree-node-cwidth (car p))
                              (undo-tree-node-rwidth (car p))))
            (throw 'need-widths (car p)))
          (setq p (cdr p))))
       ;; even number of children
       (t
        (setq p (undo-tree-node-next node))
        ;; compute left-width
        (dotimes (i (/ num-children 2))
          (if (undo-tree-node-lwidth (car p))
              (incf lwidth (+ (undo-tree-node-lwidth (car p))
                              (undo-tree-node-cwidth (car p))
                              (undo-tree-node-rwidth (car p))))
            (throw 'need-widths (car p)))
          (setq p (cdr p)))
        ;; centre-width is 0 when number of children is even
        (setq cwidth 0)
        ;; compute right-width
        (dotimes (i (/ num-children 2))
          (if (undo-tree-node-lwidth (car p))
              (incf rwidth (+ (undo-tree-node-lwidth (car p))
                              (undo-tree-node-cwidth (car p))
                              (undo-tree-node-rwidth (car p))))
            (throw 'need-widths (car p)))
          (setq p (cdr p)))))
      ;; return left-, centre- and right-widths
      (vector lwidth cwidth rwidth))))

(defun undo-tree-clear-visual-data (tree)
"Clear visualizer data below NODE."
  (undo-tree-mapc
   (lambda (n) (undo-tree-node-clear-visual-data n))
   (undo-tree-root tree)))

(defun undo-tree-node-unmodified-p (node &optional mtime)
"Return non-nil if NODE corresponds to a buffer state that once upon a
time was unmodified.  If a file modification time MTIME is specified,
return non-nil if the corresponding buffer state really is unmodified."
  (let (changeset ntime)
    (setq changeset
            (or (undo-tree-node-redo node)
                (and (setq changeset (car (undo-tree-node-next node)))
                     (undo-tree-node-undo changeset)))
          ntime
            (catch 'found
              (dolist (elt changeset)
                (when (and (consp elt)
                           (eq (car elt) t)
                           (consp (cdr elt))
                           (throw 'found (cdr elt)))))))
    (and ntime
         (or (null mtime)
             ;; high-precision timestamps
             (if (listp (cdr ntime))
               (equal ntime mtime)
               ;; old-style timestamps
               (and (= (car ntime) (car mtime))
                    (= (cdr ntime) (cadr mtime))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Visualizer drawing functions

(defun undo-tree-label-nodes--one-of-two (node)
  (let ((cur-stack (list node))
        ;; Best range is 48 to 126
        ;; numbers begin with 48
        ;; capital letters begin at 65
        ;; lowercase letters begin at number 97
        (undo-tree-branch-count 97)
        (undo-tree-branch-point-count 65)
        next-stack)
    (while (or cur-stack
               (prog1
                 (setq cur-stack next-stack)
                 (setq next-stack nil)))
      (setq node (pop cur-stack))
      (undo-tree-label-nodes--two-of-two node)
      (setq next-stack (append (undo-tree-node-next node) next-stack)))))

(defun undo-tree-label-nodes--two-of-two (node)
  (let* ((num-children (length (undo-tree-node-next node)))
         (previous-node (undo-tree-node-previous node))
         (previous-branch-point-nodes
           (when previous-node
             (undo-tree-node-next previous-node)))
         (previous-node-branch-point-p
           (when previous-branch-point-nodes
             (> (length previous-branch-point-nodes) 1)))
         (node-position--previous-node
           (when previous-node
             (undo-tree-node-position previous-node)))
         (already-labeled-p (undo-tree-node-position node)))
    ;;; handle the nth labels
    (cond
      ((and (= num-children 0) ;;; ROOT NODE WITH NO CHILDREN
            (null previous-node))
        (setf (undo-tree-node-position node) 0))
      ;;; Leaf of a branch-point and the current node is already labeled by catach-all below.
      ((and (= num-children 0)
            already-labeled-p
            previous-node-branch-point-p)
        nil)
      ;;; Leaf of a non-branch-point node.
      ((and (= num-children 0)
            node-position--previous-node)
        (setf (undo-tree-node-position node) node-position--previous-node))
      ;;; Root node with 1 child.
      ((and (= num-children 1)
            (null previous-node))
        (setf (undo-tree-node-position node) 0))
      ;;; Previous node is a branch-point and the current node is already labeled by catch-all below.
      ((and (= num-children 1)
            already-labeled-p
            previous-node-branch-point-p)
        nil)
      ;;; Node with 1 child.
      ((and (= num-children 1)
            node-position--previous-node)
        (setf (undo-tree-node-position node) node-position--previous-node))
      ;;; Branch-point:  Label each node in the list so that subsequent loops have that information.
      ;;; The current branch-point may be a child of a previous branch-point, which is a corner case.
      ;;; Use let-bound names of `current-...` and `previous--...` to prevent head from spinning.
      (t
        (let* ((current-branch-point-nodes (undo-tree-node-next node))
               (nth-previous
                 (when previous-branch-point-nodes
                   (cl-position node previous-branch-point-nodes)))
               (nth-current node-position--previous-node))
          (mapc
            (lambda (n)
              (setf (undo-tree-node-position n) (cl-position n current-branch-point-nodes)))
            current-branch-point-nodes)
          ;;; Corner case situation:  Current-branch-point is the child of a previous-branch-point.
          ;;;               o-br/pt-C-4
          ;;;               00.05.41.06
          ;;;               21.53.30.37
          ;;;               20.34.55.79
          ;;;          __________|________________
          ;;;         /          |                \
          ;;;   x-00001-i-0 o-00001-j-1       o-br/pt-D-2
          ;;;   00:05:41:07 21.53.30.38       21.52.05.52
          ;;;                                 20.34.55.80
          ;;;                                  ____|____ 
          ;;;                                 /         \
          ;;;                           o-00001-k-0 o-00001-l-1
          ;;;                           21.52.05.53 20.34.55.81
          ;;; Corner case situation:  Initial node is a branch-point.
          ;;;               x-br/pt-A-?
          ;;;               14:59:13:81
          ;;;               14.56.48.34
          ;;;                ____|____ 
          ;;;               /         \
          ;;;         o-00001-a-0 o-00001-b-1
          ;;;         14.59.13.82 14.57.17.92
          ;;;              |           |
          ;;;         o-00002-a-0 o-00002-b-1
          ;;;         14.59.13.83 14.57.17.93
          (setf (undo-tree-node-position node)
                   (cond
                     ;;; Current-branch-point is the child of a previous-branch-point.
                     ((and previous-node-branch-point-p nth-previous)
                           (cons nth-previous 'branch-point))
                     (nth-current
                       (cons nth-current 'branch-point))
                     ;;; Initial node is a branch-point.
                     ((and (null previous-node-branch-point-p)
                           (null nth-previous)
                           (null nth-current))
                       (cons 0 'branch-point))
                     (t
                       (message "previous-branch-point: %s | nth-previous: %s | nth-current: %s"
                                previous-node-branch-point-p nth-previous nth-current)
                       (cons "?" 'branch-point)))))))
    ;;; Handle the letter labels.
    (cond
      ((= num-children 0) ;; LEAF
        ;;; branch-point will be just an integer, instead of a `cons' cell.
        (if (and (undo-tree-node-previous node)
                 (consp (undo-tree-node-count (undo-tree-node-previous node))))
          (setf (undo-tree-node-count node)
                    (cons (1+ (car (undo-tree-node-count (undo-tree-node-previous node))))
                          (cdr (undo-tree-node-count (undo-tree-node-previous node)))))
          (setf (undo-tree-node-count node) (cons 1 (char-to-string undo-tree-branch-count)))
          (setq undo-tree-branch-count (1+ undo-tree-branch-count))))
      ((= num-children 1) ;; NODE WITH 1 CHILD
        ;;; branch-point will be just an integer, instead of a `cons' cell.
        (if (and (undo-tree-node-previous node)
                 (consp (undo-tree-node-count (undo-tree-node-previous node))))
          (setf (undo-tree-node-count node)
                    (cons (1+ (car (undo-tree-node-count (undo-tree-node-previous node))))
                          (cdr (undo-tree-node-count (undo-tree-node-previous node)))))
          (setf (undo-tree-node-count node) (cons 1 (char-to-string undo-tree-branch-count)))
          (setq undo-tree-branch-count (1+ undo-tree-branch-count))))
      (t
        ;;; A branch-point entry for `undo-tree-node-count' will be an integer; whereas
        ;;; a single branch or leaf entry will be a `cons' cell.
        (setf (undo-tree-node-count node) undo-tree-branch-point-count)
        (setq undo-tree-branch-point-count (1+ undo-tree-branch-point-count))))))

(defun undo-tree-draw-node (node &optional current)
"Draw symbol representing NODE in visualizer.  If CURRENT is non-nil, node is current node."
  (unless (and node (undo-tree-node-marker node))
    (let ((debug-on-quit nil))
      (signal 'quit '("undo-tree-draw-node:  Cannot locate marker!"))))
  (goto-char (undo-tree-node-marker node))
  (when (or undo-tree-visual-timestamps undo-tree-linear-history)
    (undo-tree-move-backward (/ undo-tree-visual-spacing 2)))
  (let* ((num-children (length (undo-tree-node-next node)))
         (undo-tree-insert-face
           (cond
             ((and
               undo-tree-insert-face
               (or
                 (and
                   (consp undo-tree-insert-face)
                   undo-tree-insert-face)
                 (list undo-tree-insert-face))))
             (t
               'undo-tree-visual-lazy-drawing-face)))
         (register (undo-tree-node-register node))
         (unmodified
           (if undo-tree-visual-parent-mtime
             (undo-tree-node-unmodified-p node undo-tree-visual-parent-mtime)
             (undo-tree-node-unmodified-p node)))
         (timestamps (undo-tree-node-history node))
         (timestamps--master
           (mapcar
             (lambda (x)
               (car x))
             timestamps))
          node-string)
    ;; check node's register (if any) still stores appropriate undo-tree state
    (unless (and register
                 (undo-tree-register-data-p (registerv-data (get-register register)))
                 (eq node (undo-tree-register-data-node
                            (registerv-data (get-register register)))))
      (setq register nil))
    ;; represent node by different symbols, depending on whether it's the
    ;; current node, is saved in a register, or corresponds to an unmodified buffer.
    (setq node-string
            (let ((leader
                    (cond
                      (register
                        (propertize
                          (char-to-string register)
                          'undo-tree-node node
                          'timestamp (caar timestamps)
                          'help-echo (format "mouse-2 or RET:  %s" "`r`")
                          'mouse-face 'undo-tree-mouseover-face
                          'keymap undo-tree-mouse-map))
                      (unmodified
                        (propertize "s"
                          'undo-tree-node node
                          'timestamp (caar timestamps)
                          'help-echo (format "mouse-2 or RET:  %s" "`s`")
                          'mouse-face 'undo-tree-mouseover-face
                          'keymap undo-tree-mouse-map))
                      (current
                        (propertize "x"
                          'undo-tree-node node
                          'timestamp (caar timestamps)
                          'help-echo (format "mouse-2 or RET:  %s" "`x`")
                          'mouse-face 'undo-tree-mouseover-face
                          'keymap undo-tree-mouse-map))
                      (t
                        (propertize "o"
                          'undo-tree-node node
                          'timestamp (caar timestamps)
                          'help-echo (format "mouse-2 or RET:  %s" "`o`")
                          'mouse-face 'undo-tree-mouseover-face
                          'keymap undo-tree-mouse-map)))))
              (cond
                (undo-tree-linear-history
                  (cond
                    ((= num-children 0) ;;; LEAF
                      (let ((string
                              (concat
                                " "
                                leader
                                (propertize (format "-%05d-%s-%s"
                                                (car (undo-tree-node-count node))
                                                (cdr (undo-tree-node-count node))
                                                (undo-tree-node-position node))
                                  'undo-tree-node node
                                  'timestamp (caar timestamps)
                                  'help-echo (format "mouse-2 or RET:  %s" (caar timestamps))
                                  'mouse-face 'undo-tree-mouseover-face
                                  'keymap undo-tree-mouse-map)
                                " ")))
                        string))
                    ((= num-children 1) ;;; NODE WITH 1 CHILD
                      (let ((string
                              (concat
                                " "
                                leader
                                (propertize (format "-%05d-%s-%s"
                                                (car (undo-tree-node-count node))
                                                (cdr (undo-tree-node-count node))
                                                (undo-tree-node-position node))
                                  'undo-tree-node node
                                  'timestamp (caar timestamps)
                                  'help-echo (format "mouse-2 or RET:  %s" (caar timestamps))
                                  'mouse-face 'undo-tree-mouseover-face
                                  'keymap undo-tree-mouse-map)
                                " ")))
                        string))
                    (t ;;; BRANCH-POINT
                      (let ((string
                              (concat
                                " "
                                leader
                                (propertize (format "-br/pt-%s-%s"
                                              (char-to-string (undo-tree-node-count node))
                                              ;;; Looks like:  '(nth . 'branch-point)
                                              (car (undo-tree-node-position node)))
                                  'undo-tree-node node
                                  'timestamp (caar timestamps)
                                  'help-echo (format "mouse-2 or RET:  %s" (caar timestamps))
                                  'mouse-face 'undo-tree-mouseover-face
                                  'keymap undo-tree-mouse-map)
                                " ")))
                        string))))
                (undo-tree-visual-timestamps
                  (let ((string
                          (undo-tree-timestamp-to-string
                            (undo-tree-node-timestamp node)
                            undo-tree-visual-relative-timestamps
                            current register)))
                    (propertize
                      string
                      'undo-tree-node node
                      'help-echo (format "mouse-2 or RET:  %s" "`timestamp`")
                      'mouse-face 'undo-tree-mouseover-face
                      'keymap undo-tree-mouse-map)))
                (t
                  leader)))
         undo-tree-insert-face
          (nconc
            (cond
              (current '(undo-tree-visual-current-face))
              (unmodified '(undo-tree-visual-unmodified-face))
              (register   '(undo-tree-visual-register-face)))
            undo-tree-insert-face))
    ;; draw node and link it to its representation in visualizer
    (undo-tree-insert node-string)
    (undo-tree-move-backward
      (if (or undo-tree-visual-timestamps undo-tree-linear-history)
        (1+ (/ undo-tree-visual-spacing 2))
        1))
    ;;; This marker is used to superimpose things like x-marks-the-spot!
    (move-marker (undo-tree-node-marker node) (point))
    ;;; DEBUGGING:  (message "timestamps:  %s" timestamps)
    (when undo-tree-linear-history
      (dolist (ts timestamps)
        (let* ((undo-tree-insert-face
                 (cond
                   ;;; not a branch-point
                   ;;; selected timestamp
                   ((and ts
                         (not (> num-children 1))
                         (eq (cdr ts) t))
                      'undo-tree-linear--node-selected-face)
                   ;;; branch-point
                   ((and ts
                         (> num-children 1))
                     (let ((pos (cl-position (car ts) timestamps--master))
                           (active (undo-tree-node-branch node)))
                       (cond
                         ;;; selected timstamp 20:35:02:24
                         ;;; active branch
                         ((and (= pos active)
                               (eq (cdr ts) t))
                           'undo-tree-linear--br/pt-selected-active-face)
                         ;;; selected timstamp 20:35:02:24
                         ;;; not active branch
                         ;;; @lawlist is not presently using this condition.
                         ((and (not (= pos active))
                               (eq (cdr ts) t))
                           'undo-tree-linear--br/pt-selected-inactive-face)
                         ;;; not selected timestamp 20.35.02.24
                         ;;; active branch
                         ((and (= pos active)
                               (not (eq (cdr ts) t)))
                          'undo-tree-linear--br/pt-unselected-active-face)
                         ;;; not selected timestamp 20.35.02.24
                         ;;; not active branch
                         ((and (not (= pos active))
                               (not (eq (cdr ts) t)))
                           'undo-tree-linear--br/pt-unselected-inactive-face))))
                     (t
                       ;;; not a branch-point
                       ;;; not selected timestamp
                       'undo-tree-linear--node-unselected-face)))
                 ;;; @lawlist chose to use the optional TIMEZONE argument of `t` so that the initial node
                 ;;; is `00:00:00:00`.
                 (str
                   (cond
                     ((and ts (eq (cdr ts) t))
                       (propertize (format-time-string "%H:%M:%S:%2N" (car ts) t)
                         'undo-tree-node node
                         'timestamp (car ts)
                         'help-echo (format "mouse-2 or RET:  %s" (car ts))
                         'mouse-face 'undo-tree-mouseover-face
                         'keymap undo-tree-mouse-map))
                     ((and ts (not (eq (cdr ts) t)))
                       (propertize (format-time-string "%H.%M.%S.%2N" (car ts) t)
                         'undo-tree-node node
                         'timestamp (car ts)
                         'help-echo (format "mouse-2 or RET:  %s" (car ts))
                         'mouse-face 'undo-tree-mouseover-face
                         'keymap undo-tree-mouse-map))
                     ;;; Place holder when there is no timestamp.  Useful if I ever decide
                     ;;; to play with adding timestamps and redrawing the current line.
                     (t "-----------"))))
            (when str
              (undo-tree-move-backward 5)
              (undo-tree-move-down 1)
              (undo-tree-insert str)
              (undo-tree-move-backward 6)))))))

(defun undo-tree-draw-tree (undo-tree &optional width height preserve-window-start)
"Draw undo-tree in current buffer starting from NODE, or root if nil."
  (let* ((window (selected-window))
         (window-start (window-start window))
         (node
           (if undo-tree-visual-lazy-drawing
             (undo-tree-current undo-tree)
             (undo-tree-root undo-tree)))
         (width (if width width (window-width)))
         (height (if height height (window-height))))
    (undo-tree-label-nodes--one-of-two node)
    (erase-buffer)
    (setq undo-tree-visual-needs-extending-down nil
          undo-tree-visual-needs-extending-up nil)
    (undo-tree-clear-visual-data undo-tree)
    (undo-tree-compute-widths node)
    ;; lazy drawing starts vertically centred and displaced horizontally to
    ;; the left (window-width/4), since trees will typically grow right
    (if undo-tree-visual-lazy-drawing
      (progn
        (undo-tree-move-down (/ height 2))
        (undo-tree-move-forward (max 2 (/ width 4)))) ; left margin
      ;; non-lazy drawing starts in centre at top of buffer
      (undo-tree-move-down 1)  ; top margin
      (undo-tree-move-forward
        (max
          (/ width 2)
          (+ (undo-tree-node-char-lwidth node)
             ;; add space for left part of left-most time-stamp
             (if (or undo-tree-visual-timestamps undo-tree-linear-history)
               (/ (- undo-tree-visual-spacing 4) 2)
               0)
             2))))  ; left margin
    ;; link starting node to its representation in visualizer
    (setf (undo-tree-node-marker node) (make-marker))
    (set-marker-insertion-type (undo-tree-node-marker node) nil)
    (move-marker (undo-tree-node-marker node) (point))
    ;; draw undo-tree
    (let ((undo-tree-insert-face 'undo-tree-visual-default-face)
          node-list)
      (if (not undo-tree-visual-lazy-drawing)
        (undo-tree-extend-down node t) ;; Draw the entire tree.
        (undo-tree-extend-down node)
        (undo-tree-extend-up node)
        (setq node-list undo-tree-visual-needs-extending-down
              undo-tree-visual-needs-extending-down nil)
        (while node-list
          (undo-tree-extend-down (pop node-list)))))
        ;;; Highlight the active branch.
        (let ((undo-tree-insert-face 'undo-tree-visual-active-branch-face))
          (undo-tree-highlight-active-branch (or undo-tree-visual-needs-extending-up
                                                 (undo-tree-root undo-tree))
                                             nil))
        (undo-tree-draw-node (undo-tree-current undo-tree) 'current)
        (when preserve-window-start
          (set-window-start window window-start nil))))

(defun undo-tree-extend-down (node &optional bottom)
"Extend tree downwards starting from NODE and point. If BOTTOM is t,
extend all the way down to the leaves. If BOTTOM is a node, extend down
as far as that node. If BOTTOM is an integer, extend down as far as that
line. Otherwise, only extend visible portion of tree. NODE is assumed to
already have a node marker. Returns non-nil if anything was actually extended."
  (let ((extended nil)
        (cur-stack (list node))
        next-stack)
    ;; don't bother extending if BOTTOM specifies an already-drawn node
    (unless (and (undo-tree-node-p bottom) (undo-tree-node-marker bottom))
      ;; draw nodes layer by layer
      (while (or cur-stack
                 (prog1
                   (setq cur-stack next-stack)
                   (setq next-stack nil)))
        (setq node (pop cur-stack))
        ;; if node is within range being drawn...
        (if (or (eq bottom t)
                (and (undo-tree-node-p bottom)
                     (not (eq (undo-tree-node-previous node) bottom)))
                (and (integerp bottom)
                     (>= bottom (line-number-at-pos (undo-tree-node-marker node))))
                (and (null bottom)
                     (pos-visible-in-window-p (undo-tree-node-marker node) nil t)))
            ;; ...draw one layer of node's subtree (if not already drawn)
            (progn
              (unless (and (undo-tree-node-next node)
                           (undo-tree-node-marker
                             (nth (undo-tree-node-branch node) (undo-tree-node-next node))))
                (goto-char (undo-tree-node-marker node))
                (undo-tree-draw-subtree node nil)
                (setq extended t))
              (setq next-stack (append (undo-tree-node-next node) next-stack)))
          ;; ...otherwise, postpone drawing until later
          (push node undo-tree-visual-needs-extending-down))))
    extended))

(defun undo-tree-draw-subtree (node &optional active-branch)
"Draw subtree rooted at NODE. The subtree will start from point.
If ACTIVE-BRANCH is non-nil, just draw active branch below NODE. Returns
list of nodes below NODE."
  (let ((num-children (length (undo-tree-node-next node)))
        node-list pos trunk-pos n)
    ;; draw node itself
    (undo-tree-draw-node node nil)
    (cond
      ;; if we're at a leaf node, we're done
      ((= num-children 0))
      ;; if node has only one child, draw it (not strictly necessary to deal
      ;; with this case separately, but as it's by far the most common case
      ;; this makes the code clearer and more efficient)
      ((= num-children 1)
        (undo-tree-move-down 1)
        (undo-tree-insert ?|)
        (undo-tree-move-backward 1)
        (undo-tree-move-down 1)
        (setq n (car (undo-tree-node-next node)))
        ;; link next node to its representation in visualizer
        (unless (markerp (undo-tree-node-marker n))
          (setf (undo-tree-node-marker n) (make-marker))
          (set-marker-insertion-type (undo-tree-node-marker n) nil))
        (move-marker (undo-tree-node-marker n) (point))
        ;; add next node to list of nodes to draw next
        (push n node-list))
      ;; if node has multiple children, draw branches
      (t
        (undo-tree-move-down 1)
        (undo-tree-insert ?|)
        (undo-tree-move-backward 1)
        (move-marker (setq trunk-pos (make-marker)) (point))
        ;; left subtrees
        (undo-tree-move-backward
         (- (undo-tree-node-char-lwidth node)
            (undo-tree-node-char-lwidth
             (car (undo-tree-node-next node)))))
        (move-marker (setq pos (make-marker)) (point))
        (setq n (cons nil (undo-tree-node-next node)))
        (dotimes (i (/ num-children 2))
          (setq n (cdr n))
          (when (or (null active-branch)
                    (eq (car n)
                        (nth (undo-tree-node-branch node)
                             (undo-tree-node-next node))))
            (undo-tree-move-forward 2)
            (undo-tree-insert ?_ (- trunk-pos pos 2))
            (goto-char pos)
            (undo-tree-move-forward 1)
            (undo-tree-move-down 1)
            (undo-tree-insert ?/)
            (undo-tree-move-backward 2)
            (undo-tree-move-down 1)
            ;; link node to its representation in visualizer
            (unless (markerp (undo-tree-node-marker (car n)))
              (setf (undo-tree-node-marker (car n)) (make-marker))
              (set-marker-insertion-type (undo-tree-node-marker (car n)) nil))
            (move-marker (undo-tree-node-marker (car n)) (point))
            ;; add node to list of nodes to draw next
            (push (car n) node-list))
          (goto-char pos)
          (undo-tree-move-forward
           (+ (undo-tree-node-char-rwidth (car n))
              (undo-tree-node-char-lwidth (cadr n))
              undo-tree-visual-spacing 1))
          (move-marker pos (point)))
        ;; middle subtree (only when number of children is odd)
        (when (= (mod num-children 2) 1)
          (setq n (cdr n))
          (when (or (null active-branch)
                    (eq (car n)
                        (nth (undo-tree-node-branch node)
                             (undo-tree-node-next node))))
            (undo-tree-move-down 1)
            (undo-tree-insert ?|)
            (undo-tree-move-backward 1)
            (undo-tree-move-down 1)
            ;; link node to its representation in visualizer
            (unless (markerp (undo-tree-node-marker (car n)))
              (setf (undo-tree-node-marker (car n)) (make-marker))
              (set-marker-insertion-type (undo-tree-node-marker (car n)) nil))
            (move-marker (undo-tree-node-marker (car n)) (point))
            ;; add node to list of nodes to draw next
            (push (car n) node-list))
          (goto-char pos)
          (undo-tree-move-forward
           (+ (undo-tree-node-char-rwidth (car n))
              (if (cadr n) (undo-tree-node-char-lwidth (cadr n)) 0)
              undo-tree-visual-spacing 1))
          (move-marker pos (point)))
        ;; right subtrees
        (move-marker trunk-pos (1+ trunk-pos))
        (dotimes (i (/ num-children 2))
          (setq n (cdr n))
          (when (or (null active-branch)
                    (eq (car n)
                        (nth (undo-tree-node-branch node)
                             (undo-tree-node-next node))))
            (goto-char trunk-pos)
            (undo-tree-insert ?_ (- pos trunk-pos 1))
            (goto-char pos)
            (undo-tree-move-backward 1)
            (undo-tree-move-down 1)
            (undo-tree-insert ?\\)
            (undo-tree-move-down 1)
            ;; link node to its representation in visualizer
            (unless (markerp (undo-tree-node-marker (car n)))
              (setf (undo-tree-node-marker (car n)) (make-marker))
              (set-marker-insertion-type (undo-tree-node-marker (car n)) nil))
            (move-marker (undo-tree-node-marker (car n)) (point))
            ;; add node to list of nodes to draw next
            (push (car n) node-list))
          (when (cdr n)
            (goto-char pos)
            (undo-tree-move-forward
             (+ (undo-tree-node-char-rwidth (car n))
                (if (cadr n) (undo-tree-node-char-lwidth (cadr n)) 0)
                undo-tree-visual-spacing 1))
            (move-marker pos (point))))))
    ;; return list of nodes to draw next
    (nreverse node-list)))

(defun undo-tree-extend-up (node &optional top)
"Extend tree upwards starting from NODE. If TOP is t, extend all the way
to root. If TOP is a node, extend up as far as that node. If TOP is an
integer, extend up as far as that line. Otherwise, only extend visible
portion of tree. NODE is assumed to already have a node marker. Returns
non-nil if anything was actually extended."
  (let ((extended nil)
        parent)
    ;; don't bother extending if TOP specifies an already-drawn node
    (unless (and (undo-tree-node-p top) (undo-tree-node-marker top))
      (while node
        (setq parent (undo-tree-node-previous node))
        ;; if we haven't reached root...
        (if parent
            ;; ...and node is within range being drawn...
            (if (or (eq top t)
                    (and (undo-tree-node-p top) (not (eq node top)))
                    (and (integerp top)
                         (< top (line-number-at-pos (undo-tree-node-marker node))))
                    (and (null top)
                         ;;; NOTE: we check point in case window-start is outdated
                         (< (min (line-number-at-pos (point)) (line-number-at-pos (window-start)))
                                 (line-number-at-pos (undo-tree-node-marker node)))))
          ;; ...and it hasn't already been drawn
          (when (not (undo-tree-node-marker parent))
            ;; link parent node to its representation in visualizer
            (undo-tree-compute-widths parent)
            (undo-tree-move-to-parent node)
            (setf (undo-tree-node-marker parent) (make-marker))
            (set-marker-insertion-type (undo-tree-node-marker parent) nil)
            (move-marker (undo-tree-node-marker parent) (point))
            ;; draw subtree beneath parent
            (setq undo-tree-visual-needs-extending-down
            (nconc (delq node (undo-tree-draw-subtree parent nil))
                   undo-tree-visual-needs-extending-down))
            (setq extended t))
              ;; ...otherwise, postpone drawing for later and exit
              (setq undo-tree-visual-needs-extending-up (when parent node)
              parent nil))
          ;; if we've reached root, stop extending and add top margin
          (setq undo-tree-visual-needs-extending-up nil)
          (goto-char (undo-tree-node-marker node))
          (undo-tree-move-up 1)  ; top margin
          (delete-region (point-min) (line-beginning-position)))
        ;; next iteration
        (setq node parent)))
    extended))

(defun undo-tree-expand-down (from &optional to)
"Expand tree downwards. FROM is the node to start expanding from. Stop
expanding at TO if specified. Otherwise, just expand visible portion of
tree and highlight active branch from FROM."
  (when undo-tree-visual-needs-extending-down
    (let ((inhibit-read-only t)
          node-list extended)
      ;; extend down as far as TO node
      (when to
        (setq extended (undo-tree-extend-down from to))
        (goto-char (undo-tree-node-marker to))
        (redisplay t))  ; force redisplay to scroll buffer if necessary
      ;; extend visible portion of tree downwards
      (setq node-list undo-tree-visual-needs-extending-down
      undo-tree-visual-needs-extending-down nil)
      (when node-list
  (dolist (n node-list)
    (when (undo-tree-extend-down n) (setq extended t)))
  ;; highlight active branch in newly-extended-down portion, if any
  (when extended
    (let ((undo-tree-insert-face 'undo-tree-visual-active-branch-face))
      (undo-tree-highlight-active-branch from nil)))))))

(defun undo-tree-expand-up (from &optional to)
"Expand tree upwards. FROM is the node to start expanding from, TO is the
node to stop expanding at. If TO node isn't specified, just expand visible
portion of tree and highlight active branch down to FROM."
  (when undo-tree-visual-needs-extending-up
    (let ((inhibit-read-only t)
          extended node-list)
      ;; extend up as far as TO node
      (when to
        (setq extended (undo-tree-extend-up from to))
        (goto-char (undo-tree-node-marker to))
        ;; simulate auto-scrolling if close to top of buffer
        (when (<= (line-number-at-pos (point)) scroll-margin)
          (undo-tree-move-up (if (= scroll-conservatively 0)
               (/ (window-height) 2) 3))
          (when (undo-tree-extend-up to) (setq extended t))
          (goto-char (undo-tree-node-marker to))
          (unless (= scroll-conservatively 0) (recenter scroll-margin))))
      ;; extend visible portion of tree upwards
      (and undo-tree-visual-needs-extending-up
     (undo-tree-extend-up undo-tree-visual-needs-extending-up)
     (setq extended t))
      ;; extend visible portion of tree downwards
      (setq node-list undo-tree-visual-needs-extending-down
      undo-tree-visual-needs-extending-down nil)
      (dolist (n node-list)
        (undo-tree-extend-down n))
      ;; highlight active branch in newly-extended-up portion, if any
      (when extended
        (let ((undo-tree-insert-face 'undo-tree-visual-active-branch-face))
          (undo-tree-highlight-active-branch
            (or undo-tree-visual-needs-extending-up (undo-tree-root undo-tree-list))
            from))))))

(defun undo-tree-highlight-active-branch (node &optional end)
"Draw highlighted active branch below NODE in current buffer.
Stop highlighting at END node if specified."
  (let ((stack (list node)))
    ;; draw active branch
    (while stack
      (setq node (pop stack))
      (unless (or (eq node end)
                  (memq node undo-tree-visual-needs-extending-down))
       (goto-char (undo-tree-node-marker node))
       (setq node (undo-tree-draw-subtree node 'active)
                  stack (nconc stack node))))))

(defun undo-tree-node-char-lwidth (node)
"Return left-width of NODE measured in characters."
  (if (= (length (undo-tree-node-next node)) 0) 0
    (- (* (+ undo-tree-visual-spacing 1) (undo-tree-node-lwidth node))
       (if (= (undo-tree-node-cwidth node) 0)
           (1+ (/ undo-tree-visual-spacing 2)) 0))))

(defun undo-tree-node-char-rwidth (node)
"Return right-width of NODE measured in characters."
  (if (= (length (undo-tree-node-next node)) 0) 0
    (- (* (+ undo-tree-visual-spacing 1) (undo-tree-node-rwidth node))
       (if (= (undo-tree-node-cwidth node) 0)
           (1+ (/ undo-tree-visual-spacing 2)) 0))))

(defun undo-tree-insert (str &optional arg)
"Insert character or string STR ARG times, overwriting, and using `undo-tree-insert-face'."
  (unless arg (setq arg 1))
  (when (characterp str)
    (setq str (make-string arg str))
    (setq arg 1))
  (dotimes (i arg) (insert str))
  (setq arg (* arg (length str)))
  (undo-tree-move-forward arg)
  ;; make sure mark isn't active, otherwise `backward-delete-char' might
  ;; delete region instead of single char if transient-mark-mode is enabled
  (setq mark-active nil)
  (backward-delete-char arg)
  (when undo-tree-insert-face
    (put-text-property (- (point) arg) (point) 'face undo-tree-insert-face)))

(defun undo-tree-move-down (&optional arg)
"Move down, extending buffer if necessary."
  (let* ((row (line-number-at-pos))
         (col (current-column))
         line)
    (unless arg (setq arg 1))
    (forward-line arg)
    (setq line (line-number-at-pos))
    ;; if buffer doesn't have enough lines, add some
    (when (/= line (+ row arg))
      (cond
       ((< arg 0)
  (insert (make-string (- line row arg) ?\n))
  (forward-line (+ arg (- row line))))
       (t (insert (make-string (- arg (- line row)) ?\n)))))
    (undo-tree-move-forward col)))

(defun undo-tree-move-up (&optional arg)
"Move up, extending buffer if necessary."
  (unless arg (setq arg 1))
  (undo-tree-move-down (- arg)))

(defun undo-tree-move-forward (&optional arg)
"Move forward, extending buffer if necessary."
  (unless arg (setq arg 1))
  (let (n)
    (cond
     ((>= arg 0)
      (setq n (- (line-end-position) (point)))
      (if (> n arg)
    (forward-char arg)
  (end-of-line)
  (insert (make-string (- arg n) ? ))))
     ((< arg 0)
      (setq arg (- arg))
      (setq n (- (point) (line-beginning-position)))
      (when (< (- n 2) arg)  ; -2 to create left-margin
  ;; no space left - shift entire buffer contents right!
  (let ((pos (move-marker (make-marker) (point))))
    (set-marker-insertion-type pos t)
    (goto-char (point-min))
    (while (not (eobp))
      (insert-before-markers (make-string (- arg -2 n) ? ))
      (forward-line 1))
    (goto-char pos)))
      (backward-char arg)))))

(defun undo-tree-move-backward (&optional arg)
"Move backward, extending buffer if necessary."
  (unless arg (setq arg 1))
  (undo-tree-move-forward (- arg)))

(defun undo-tree-move-to-parent (node)
"Move to position of parent of NODE, extending buffer if necessary."
  (let* ((parent (undo-tree-node-previous node))
   (n (undo-tree-node-next parent))
   (l (length n)) p)
    (goto-char (undo-tree-node-marker node))
    (unless (= l 1)
      ;; move horizontally
      (setq p (undo-tree-position node n))
      (cond
       ;; node in centre subtree: no horizontal movement
       ((and (= (mod l 2) 1) (= p (/ l 2))))
       ;; node in left subtree: move right
       ((< p (/ l 2))
  (setq n (nthcdr p n))
  (undo-tree-move-forward
   (+ (undo-tree-node-char-rwidth (car n))
      (/ undo-tree-visual-spacing 2) 1))
  (dotimes (i (- (/ l 2) p 1))
    (setq n (cdr n))
    (undo-tree-move-forward
     (+ (undo-tree-node-char-lwidth (car n))
        (undo-tree-node-char-rwidth (car n))
        undo-tree-visual-spacing 1)))
  (when (= (mod l 2) 1)
    (setq n (cdr n))
    (undo-tree-move-forward
     (+ (undo-tree-node-char-lwidth (car n))
        (/ undo-tree-visual-spacing 2) 1))))
       (t ;; node in right subtree: move left
  (setq n (nthcdr (/ l 2) n))
  (when (= (mod l 2) 1)
    (undo-tree-move-backward
     (+ (undo-tree-node-char-rwidth (car n))
        (/ undo-tree-visual-spacing 2) 1))
    (setq n (cdr n)))
  (dotimes (i (- p (/ l 2) (mod l 2)))
    (undo-tree-move-backward
     (+ (undo-tree-node-char-lwidth (car n))
        (undo-tree-node-char-rwidth (car n))
        undo-tree-visual-spacing 1))
    (setq n (cdr n)))
  (undo-tree-move-backward
   (+ (undo-tree-node-char-lwidth (car n))
      (/ undo-tree-visual-spacing 2) 1)))))
    ;; move vertically
    (undo-tree-move-up 3)))

(defun undo-tree-timestamp-to-string (timestamp &optional relative current register)
"Convert TIMESTAMP to string (either absolute or RELATVE time), indicating
if it's the CURRENT node and/or has an associated REGISTER."
  (if relative
      ;; relative time
      (let ((time (floor (float-time
        (subtract-time (current-time) timestamp))))
      n)
  (setq time
        ;; years
        (if (> (setq n (/ time 315360000)) 0)
      (if (> n 999) "-ages" (format "-%dy" n))
    (setq time (% time 315360000))
    ;; days
    (if (> (setq n (/ time 86400)) 0)
        (format "-%dd" n)
      (setq time (% time 86400))
      ;; hours
      (if (> (setq n (/ time 3600)) 0)
          (format "-%dh" n)
        (setq time (% time 3600))
        ;; mins
        (if (> (setq n (/ time 60)) 0)
      (format "-%dm" n)
          ;; secs
          (format "-%ds" (% time 60)))))))
  (setq time (concat
        (if current "*" " ")
        time
        (if register (concat "[" (char-to-string register) "]")
          "   ")))
  (setq n (length time))
  (if (< n 9)
      (concat (make-string (- 9 n) ? ) time)
    time))
    ;; absolute time
    (concat (if current " *" "  ")
      (format-time-string "%H:%M:%S" timestamp)
      (if register
    (concat "[" (char-to-string register) "]")
        "   "))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Visualizer commands

(define-derived-mode undo-tree-visual-mode special-mode "undo-tree-visual"
  "Major mode used in undo-tree visualizer.
-  The undo-tree visualizer can only be invoked from a buffer in
which `undo-tree-mode' is enabled. The visualizer displays the
undo history tree graphically, and allows you to browse around
the undo history, undoing or redoing the corresponding changes in
the parent buffer.
-  Within the undo-tree visualizer, the following keys are available:
  \\{undo-tree-visual-mode-map}"
  :syntax-table nil
  :abbrev-table nil
  (let ((undo-tree--mode-line-format
          (list
            "%e"
            'mode-line-front-space
            'mode-line-mule-info
            'mode-line-client
            'mode-line-modified
            'mode-line-remote
            'mode-line-frame-identification
            'mode-line-buffer-identification
            "   "
            (propertize (format "%s" (undo-tree-count undo-tree-list)) 'face 'undo-tree-visual-mode-line-face)
            "   "
            'mode-line-position
            '(lvc-mode lvc-mode)
            "  "
            'mode-line-modes
            'mode-line-misc-info
            'mode-line-end-spaces)))
    (when current-prefix-arg
      (setq undo-tree-linear-history t))
    (setq mode-line-format undo-tree--mode-line-format)
    (setq buffer-undo-list t)
    (setq truncate-lines t)
    (setq cursor-type nil)
    (setq undo-tree-visual-selected-node nil)
    (setq undo-tree-visual-parent-mtime
            (and (buffer-file-name undo-tree-visual-parent-buffer)
                 (nth 5 (file-attributes (buffer-file-name undo-tree-visual-parent-buffer)))))
    (setq undo-tree-visual-initial-node (undo-tree-current undo-tree-list))
    (setq undo-tree-visual-spacing (undo-tree-visual-calculate-spacing))
    (set (make-local-variable 'undo-tree-visual-lazy-drawing)
           (or (eq undo-tree-visual-lazy-drawing t)
               (and (numberp undo-tree-visual-lazy-drawing)
              (>= (undo-tree-count undo-tree-list)
                  undo-tree-visual-lazy-drawing))))
    (when undo-tree-visual-diff
      (undo-tree-visual-show-diff))
    (let ((inhibit-read-only t))
      (undo-tree-draw-tree undo-tree-list (if current-prefix-arg 70 60) (window-height)))))

(defun undo-tree-visual (arg)
"Visualize the current buffer's undo tree."
(interactive "P")
  (when (eq buffer-undo-list t)
    (user-error "undo-tree-visual:  No undo information in this buffer!"))
  (undo-tree-transfer-list)
  (add-hook 'before-change-functions 'undo-tree-kill-visual nil t)
  (let ((parent-buffer (current-buffer))
        (undo-tree undo-tree-list)
        (display-buffer-mark-dedicated 'soft)
        (visualize-buffer (get-buffer-create undo-tree-visual-buffer-name)))
    (with-current-buffer visualize-buffer
      (setq undo-tree-list undo-tree)
      (setq undo-tree-visual-parent-buffer parent-buffer)
      (undo-tree-visual-mode))
    (display-buffer
      visualize-buffer
      `((display-buffer-reuse-window display-buffer-pop-up-window)
        (window-width . ,(if arg 70 60))))
    (when (get-buffer-window undo-tree-visual-buffer-name)
      (let ((visualize-window (get-buffer-window undo-tree-visual-buffer-name))
            (x-marks-the-spot
              (marker-position (undo-tree-node-marker (undo-tree-current undo-tree-list)))))
        (unless (pos-visible-in-window-p x-marks-the-spot visualize-window)
          (set-window-point visualize-window x-marks-the-spot)
          (with-selected-window visualize-window
            (cond
              ((< x-marks-the-spot (window-start visualize-window))
                (recenter 2))
              ((> x-marks-the-spot (window-end visualize-window t))
                (recenter -2)))))))))

(defun undo-tree-visual-classic-undo (arg)
"Undo changes.  Repeat this command to undo more changes.
A numeric ARG serves as a repeat count.
In Transient Mark mode when the mark is active, only undo changes
within the current region. Similarly, when not in Transient Mark
mode, just \\[universal-argument] as an argument limits undo to
changes within the current region."
(interactive "P")
  (undo-tree-visual--undo-or-redo arg 'undo)
  (undo-tree-announce-branch-point "undo-tree-visual-classic-undo"))

(defun undo-tree-visual-classic-redo (arg)
"Redo changes. A numeric ARG serves as a repeat count.
In Transient Mark mode when the mark is active, only redo changes
within the current region. Similarly, when not in Transient Mark
mode, just \\[universal-argument] as an argument limits redo to
changes within the current region."
(interactive "P")
  (undo-tree-visual--undo-or-redo arg 'redo)
  (undo-tree-announce-branch-point "undo-tree-visual-classic-redo"))

(defun undo-tree-visual-linear-undo (arg)
"Undo changes.  Repeat this command to undo more changes.
A numeric ARG serves as a repeat count.
In Transient Mark mode when the mark is active, only undo changes
within the current region. Similarly, when not in Transient Mark
mode, just \\[universal-argument] as an argument limits undo to
changes within the current region."
(interactive "P")
  (undo-tree-visual--undo-or-redo (or arg -1) 'linear)
  (undo-tree-announce-branch-point "undo-tree-visual-linear-undo"))

(defun undo-tree-visual-linear-redo (arg)
"Redo changes. A numeric ARG serves as a repeat count.
In Transient Mark mode when the mark is active, only redo changes
within the current region. Similarly, when not in Transient Mark
mode, just \\[universal-argument] as an argument limits redo to
changes within the current region."
(interactive "P")
  (undo-tree-visual--undo-or-redo (or arg 1) 'linear)
  (undo-tree-announce-branch-point "undo-tree-visual-linear-redo"))

;;;   (undo-tree-map-active-branch (undo-tree-root undo-tree-list))
;;;   (length (undo-tree-map-active-branch (undo-tree-root undo-tree-list)))
(defun undo-tree-map-active-branch (node &optional end)
  (let ((stack (list node))
        res)
    (while stack
      (setq node (pop stack))
      (push node res)
      (unless (or (eq node end)
                  (memq node undo-tree-visual-needs-extending-down))
        (setq node
               (let ((num-children (length (undo-tree-node-next node)))
                     node-list pos trunk-pos n)
                 (cond
                   ((= num-children 0))
                   ((= num-children 1)
                     (setq n (car (undo-tree-node-next node)))
                     (push n node-list))
                   (t
                     (setq n (cons nil (undo-tree-node-next node)))
                     (dotimes (i (/ num-children 2))
                       (setq n (cdr n))
                       (when (or (eq (car n)
                                     (nth (undo-tree-node-branch node)
                                          (undo-tree-node-next node))))
                         (push (car n) node-list)))
                     (when (= (mod num-children 2) 1)
                       (setq n (cdr n))
                       (when (or (eq (car n)
                                     (nth (undo-tree-node-branch node)
                                          (undo-tree-node-next node))))
                         (push (car n) node-list)))
                     (dotimes (i (/ num-children 2))
                       (setq n (cdr n))
                       (when (or (eq (car n)
                                     (nth (undo-tree-node-branch node)
                                          (undo-tree-node-next node))))
                         (push (car n) node-list)))))
                 (nreverse node-list)))
        (setq stack (nconc stack node))))
    res))

(defun undo-tree-visual--undo-or-redo (arg action)
"undo/redo changes. A numeric ARG serves as a repeat count."
(interactive "P")
  (let ((parent-buffer ;; get buffer-local in the visualizer buffer
          (with-current-buffer undo-tree-visual-buffer-name
            undo-tree-visual-parent-buffer))
        (previous-active-branch
          (undo-tree-map-active-branch (undo-tree-root undo-tree-list)))
        (old (undo-tree-current undo-tree-list))
        current)
    (unwind-protect
      (with-current-buffer parent-buffer
        (deactivate-mark)
        (let ((undo-tree-inhibit-kill-visual t))
          (cond
            ((eq action 'undo)
              (undo-tree--undo-or-redo arg 'undo nil nil nil))
            ((eq action 'redo)
              (undo-tree--undo-or-redo arg 'redo nil nil nil))
            ((eq action 'linear)
              (undo-tree-linear--undo-or-redo arg))))
         (setq current (undo-tree-current undo-tree-list)))
      (unless current
        (let ((debug-on-quit nil))
          (signal 'quit '("undo-tree-visual--undo-or-redo:  end of the road!"))))
      ;;; If there are no previous or next nodes, then we are done here.
      (with-current-buffer undo-tree-visual-buffer-name
        ;;; UN-highlight old current node
        (cond
          ((eq action 'linear)
            (let ((previous-branch (undo-tree-node-position old))
                  (current-branch (undo-tree-node-position current)))
              ;;; A branch-point arrival need not necessarily trigger a full redraw.
              ;;; First, test to make sure that the current node is a `memq' of the
              ;;; PREVIOUS-ACTIVE-BRANCH.  Second, test to make sure there is no
              ;;; child that is a non-`memq' of the PREVIOUS ACTIVE-BRANCH.
              (if (and (memq current previous-active-branch)
                       (not (and (undo-tree-node-next current)
                                  (not (memq (nth (undo-tree-node-branch current) (undo-tree-node-next current)) previous-active-branch)))))
                (let ((inhibit-read-only t)
                      (undo-tree-insert-face 'undo-tree-visual-active-branch-face))
                  (undo-tree-draw-node old nil))
                ;;; redraw the entire tree
                (let ((inhibit-read-only t))
                  (undo-tree-draw-tree undo-tree-list nil nil 'preserve-window-start)))))
          (t
            (let ((undo-tree-insert-face 'undo-tree-visual-active-branch-face)
                  (inhibit-read-only t))
              (undo-tree-draw-node old nil))))
        ;;; when using lazy drawing, extend tree upwards/downwards as required
        (when undo-tree-visual-lazy-drawing
          (cond
            ((eq action 'undo)
              (undo-tree-expand-up old current))
            ((eq action 'redo)
              (undo-tree-expand-down old current))
            ((and (eq action 'linear)
                  (> arg 0))
              (undo-tree-expand-down old current))
            ((and (eq action 'linear)
                  (< arg 0))
              (undo-tree-expand-up old current))))
        ;;; highlight new current node
        (let ((inhibit-read-only t))
          (undo-tree-draw-node current 'current))
        ;;; update diff display, if any
        (when undo-tree-visual-diff
          (undo-tree-visual-update-diff))
        (when (get-buffer-window undo-tree-visual-buffer-name)
          (let ((visualize-window (get-buffer-window undo-tree-visual-buffer-name))
                (x-marks-the-spot
                  (marker-position (undo-tree-node-marker (undo-tree-current undo-tree-list)))))
            (unless (pos-visible-in-window-p x-marks-the-spot visualize-window)
              (set-window-point visualize-window x-marks-the-spot)
              (with-selected-window visualize-window
                (cond
                  ((< x-marks-the-spot (window-start visualize-window))
                    (recenter 2))
                  ((> x-marks-the-spot (window-end visualize-window t))
                    (recenter -2)))))))))))

(defun undo-tree-visual-switch-branch-right (arg)
"Switch to next branch of the undo tree.
This will affect which branch to descend when *redoing* changes
using `undo-tree-classic-redo' or `undo-tree-visual-classic-redo'."
(interactive "p")
  (unless (undo-tree-node-marker (undo-tree-current undo-tree-list))
    (let ((debug-on-quit nil))
      (signal 'quit '("undo-tree-visual-switch-branch-right:  Cannot locate marker!"))))
  ;; sanity check branch number
  (when (<= (undo-tree-num-branches) 1)
    (user-error "Not at a branch point."))
  ;; UN-highlight old active branch below current node
  (goto-char (undo-tree-node-marker (undo-tree-current undo-tree-list)))
  (let ((inhibit-read-only t))
    (let ((undo-tree-insert-face 'undo-tree-visual-default-face))
      (undo-tree-highlight-active-branch (undo-tree-current undo-tree-list) nil)))
  ;; increment branch
  (let ((branch (undo-tree-node-branch (undo-tree-current undo-tree-list))))
    (setf (undo-tree-node-branch (undo-tree-current undo-tree-list))
           (cond
            ((>= (+ branch arg) (undo-tree-num-branches))
             (1- (undo-tree-num-branches)))
            ((<= (+ branch arg) 0) 0)
            (t (+ branch arg))))
    (let* ((current-node (undo-tree-current undo-tree-list))
           (timestamps (undo-tree-node-history current-node))
           (position (undo-tree-node-branch current-node))
           (target-timestamp (car (nth position timestamps))))
      (undo-tree-set-timestamp (undo-tree-previous undo-tree-list) 'off nil)
      (undo-tree-set-timestamp nil 'on target-timestamp))
    (let ((inhibit-read-only t))
      ;; highlight new active branch below current node
      (goto-char (undo-tree-node-marker (undo-tree-current undo-tree-list)))
      (let ((undo-tree-insert-face 'undo-tree-visual-active-branch-face))
        (undo-tree-highlight-active-branch (undo-tree-current undo-tree-list) nil))
      ;; re-highlight current node
      (undo-tree-draw-node (undo-tree-current undo-tree-list) 'current))))

(defun undo-tree-visual-switch-branch-left (arg)
"Switch to previous branch of the undo tree.
This will affect which branch to descend when *redoing* changes
using `undo-tree-classic-redo' or `undo-tree-visual-classic-redo'."
(interactive "p")
  (unless (undo-tree-node-marker (undo-tree-current undo-tree-list))
    (let ((debug-on-quit nil))
      (signal 'quit '("undo-tree-visual-switch-branch-left:  Cannot locate marker!"))))
  (undo-tree-visual-switch-branch-right (- arg)))

(defun undo-tree-kill-visual (&rest _dummy)
"Kill visualizer. Added to `before-change-functions' hook of original
buffer when visualizer is invoked."
  (unless (or undo-tree-inhibit-kill-visual
              (null (get-buffer undo-tree-visual-buffer-name)))
    (undo-tree-visual-quit)))

(defun undo-tree-visual-quit ()
"Quit the undo-tree visualizer."
(interactive)
  (when (get-buffer undo-tree-visual-buffer-name)
    (let* ((+-redraw-hook nil)
           (parent-buffer
             (with-current-buffer undo-tree-visual-buffer-name
               undo-tree-visual-parent-buffer))
           (parent-window (get-buffer-window parent-buffer))
           (visualize-window (get-buffer-window undo-tree-visual-buffer-name)))
      ;; remove kill visualizer hook from parent buffer
      (unwind-protect
        (when (and (get-buffer parent-buffer)
                   (buffer-live-p parent-buffer))
          (with-current-buffer parent-buffer
            (undo-tree-clear-visual-data undo-tree-list)
            (remove-hook 'before-change-functions 'undo-tree-kill-visual t)))
        ;; kill diff buffer, if any
        (when undo-tree-visual-diff
          (undo-tree-visual-hide-diff))
       (kill-buffer undo-tree-visual-buffer-name)))))

(defun undo-tree-visual-abort ()
"Quit the undo-tree visualizer and return buffer to original state."
(interactive)
  (let ((node undo-tree-visual-initial-node))
    (undo-tree-visual-quit)
    (undo-tree-set node)))

(defun undo-tree-visual-set (&optional pos node-or-number)
"Set buffer to state corresponding to undo tree node
at POS, or point if POS is nil."
(interactive)
  (unless pos (setq pos (point)))
  (let* ((props (text-properties-at pos))
         (target-timestamp (plist-get props 'timestamp))
         (node
           (cond
             ((and node-or-number (vectorp node-or-number))
               node-or-number)
             (t
               (plist-get props 'undo-tree-node)))))
    (when node
      ;; set parent buffer to state corresponding to node at POS
      (with-current-buffer undo-tree-visual-parent-buffer
        (let ((undo-tree-inhibit-kill-visual t))
          (undo-tree-set node nil target-timestamp)
          ;; inform user if at branch point
          (undo-tree-announce-branch-point "undo-tree-visual-set")))
      (with-current-buffer undo-tree-visual-buffer-name
        ;; re-draw undo tree
        (let ((inhibit-read-only t))
          (undo-tree-draw-tree undo-tree-list nil nil 'preserve-window-start))
        (when undo-tree-visual-diff
          (undo-tree-visual-update-diff))))))

(defun undo-tree-visual-undo-to-x (&optional x)
"Undo to last branch point, register, or saved state.
If X is the symbol `branch', undo to last branch point. If X is
the symbol `register', undo to last register. If X is the sumbol
`saved', undo to last saved state. If X is null, undo to first of
these that's encountered.
Interactively, a single \\[universal-argument] specifies
`branch', a double \\[universal-argument] \\[universal-argument]
specifies `saved', and a negative prefix argument specifies
`register'."
(interactive "P")
  (when (and (called-interactively-p 'any) x)
    (setq x (prefix-numeric-value x)
          x (cond
              ((< x 0)
                'register)
              ((<= x 4)
                'branch)
              (t
                'saved))))
  (let ((current
          (if undo-tree-visual-selection-mode
            undo-tree-visual-selected-node
            (undo-tree-current undo-tree-list)))
        (diff undo-tree-visual-diff)
        r)
    (undo-tree-visual-hide-diff)
    (while (and (undo-tree-node-previous current)
                (or (if undo-tree-visual-selection-mode
                      (progn
                        (undo-tree-visual-select-previous)
                        (setq current undo-tree-visual-selected-node))
                      (undo-tree-visual-classic-undo nil)
                      (setq current (undo-tree-current undo-tree-list)))
                    t)
                ;; branch point
                (not (or (and (or (null x) (eq x 'branch))
                              (> (undo-tree-num-branches) 1))
                         ;; register
                         (and (or (null x) (eq x 'register))
                              (setq r (undo-tree-node-register current))
                              (undo-tree-register-data-p
                                (setq r (registerv-data (get-register r))))
                              (eq current (undo-tree-register-data-node r)))
                         ;; saved state
                         (and (or (null x) (eq x 'saved))
                              (undo-tree-node-unmodified-p current))))))
    ;; update diff display, if any
    (when diff
      (undo-tree-visual-show-diff
       (when undo-tree-visual-selection-mode
         undo-tree-visual-selected-node)))))

(defun undo-tree-visual-redo-to-x (&optional x)
"Redo to last branch point, register, or saved state.
If X is the symbol `branch', redo to last branch point. If X is
the symbol `register', redo to last register. If X is the sumbol
`saved', redo to last saved state. If X is null, redo to first of
these that's encountered.
Interactively, a single \\[universal-argument] specifies
`branch', a double \\[universal-argument] \\[universal-argument]
specifies `saved', and a negative prefix argument specifies
`register'."
(interactive "P")
  (when (and (called-interactively-p 'any) x)
    (setq x (prefix-numeric-value x)
          x (cond
              ((< x 0)
                'register)
              ((<= x 4)
                'branch)
              (t
                'saved))))
  (let ((current
          (if undo-tree-visual-selection-mode
            undo-tree-visual-selected-node
            (undo-tree-current undo-tree-list)))
        (diff undo-tree-visual-diff)
        r)
    (undo-tree-visual-hide-diff)
    (while (and (undo-tree-node-next current)
                (or (if undo-tree-visual-selection-mode
                      (progn
                        (undo-tree-visual-select-next)
                        (setq current undo-tree-visual-selected-node))
                      (undo-tree-visual-classic-redo nil)
                      (setq current (undo-tree-current undo-tree-list)))
                    t)
                ;; branch point
                (not (or (and (or (null x) (eq x 'branch))
                              (> (undo-tree-num-branches) 1))
                         ;; register
                         (and (or (null x) (eq x 'register))
                              (setq r (undo-tree-node-register current))
                              (undo-tree-register-data-p
                                (setq r (registerv-data (get-register r))))
                              (eq current (undo-tree-register-data-node r)))
                         ;; saved state
                         (and (or (null x) (eq x 'saved))
                              (undo-tree-node-unmodified-p current))))))
    ;; update diff display, if any
    (when diff
      (undo-tree-visual-show-diff
        (when undo-tree-visual-selection-mode
          undo-tree-visual-selected-node)))))

;; calculate horizontal spacing required for drawing tree with current settings
(defsubst undo-tree-visual-calculate-spacing ()
  (cond
    (undo-tree-linear-history
      13)
    (undo-tree-visual-timestamps
      (if undo-tree-visual-relative-timestamps
        9
        13))
    (t
      3)))

(defun undo-tree-visual-toggle-timestamps ()
"Toggle display of linear time-stamps."
(interactive)
  (cond
    (undo-tree-visual-timestamps
      (setq undo-tree-visual-timestamps nil
            undo-tree-linear-history t)
      (unless (one-window-p)
        (enlarge-window-horizontally 10)))
    (undo-tree-linear-history
      (setq undo-tree-linear-history nil)
      (unless (one-window-p)
        (shrink-window-horizontally 20)))
    ((null undo-tree-visual-timestamps)
      (setq undo-tree-visual-timestamps t)
      (unless (one-window-p)
        (enlarge-window-horizontally 10))))
  (let ((inhibit-read-only t))
    (setq undo-tree-visual-spacing (undo-tree-visual-calculate-spacing))
    (undo-tree-draw-tree undo-tree-list)))

(defun undo-tree-visual-mouse-set (pos)
"Set buffer to state corresponding to undo tree node
at mouse event POS."
(interactive "@e")
  (undo-tree-visual-set (event-start (nth 1 pos))))

(defun undo-tree-visual-scroll-left (&optional arg)
  (interactive "p")
  (scroll-left (or arg 1) t))

(defun undo-tree-visual-scroll-right (&optional arg)
  (interactive "p")
  (scroll-right (or arg 1) t))

(defun undo-tree-visual-scroll-up (&optional arg)
  (interactive "P")
  (if (or (and (numberp arg) (< arg 0)) (eq arg '-))
      (undo-tree-visual-scroll-down arg)
    ;; scroll up and expand newly-visible portion of tree
    (unwind-protect
  (scroll-up-command arg)
      (undo-tree-expand-down
       (nth (undo-tree-node-branch (undo-tree-current undo-tree-list))
      (undo-tree-node-next (undo-tree-current undo-tree-list)))))
    ;; signal error if at eob
    (when (and (not undo-tree-visual-needs-extending-down) (eobp))
      (scroll-up))))

(defun undo-tree-visual-scroll-down (&optional arg)
  (interactive "P")
  (if (or (and (numberp arg) (< arg 0)) (eq arg '-))
      (undo-tree-visual-scroll-up arg)
    ;; ensure there's enough room at top of buffer to scroll
    (let* ((scroll-lines
             (or arg (- (window-height) next-screen-context-lines)))
           (window-line (1- (line-number-at-pos (window-start)))))
      (when (and undo-tree-visual-needs-extending-up
     (< window-line scroll-lines))
  (let ((inhibit-read-only t))
    (goto-char (point-min))
    (undo-tree-move-up (- scroll-lines window-line)))))
    ;; scroll down and expand newly-visible portion of tree
    (unwind-protect
  (scroll-down-command arg)
      (undo-tree-expand-up
       (undo-tree-node-previous (undo-tree-current undo-tree-list))))
    ;; signal error if at bob
    (when (and (not undo-tree-visual-needs-extending-down) (bobp))
      (scroll-down))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Visualizer selection mode

(define-minor-mode undo-tree-visual-selection-mode
  "Toggle mode to select nodes in undo-tree visualizer."
  :lighter "Select"
  :keymap undo-tree-visual-selection-mode-map
  :group undo-tree
  (cond
   ;; enable selection mode
    (undo-tree-visual-selection-mode
      (setq cursor-type 'box)
      (setq undo-tree-visual-selected-node
      (undo-tree-current undo-tree-list))
      ;; erase diff (if any), as initially selected node is identical to current
      (when undo-tree-visual-diff
        (let ((buff (get-buffer undo-tree-diff-buffer-name))
              (inhibit-read-only t))
          (when buff
            (with-current-buffer buff
              (erase-buffer))))))
    (t ;; disable selection mode
     (setq cursor-type nil)
     (setq undo-tree-visual-selected-node nil)
     (goto-char (undo-tree-node-marker (undo-tree-current undo-tree-list)))
     (when undo-tree-visual-diff
        (undo-tree-visual-update-diff)))))

(defun undo-tree-visual-select-previous (&optional arg)
"Move to previous node."
(interactive "p")
  (let ((node undo-tree-visual-selected-node))
    (catch 'top
      (dotimes (i (or arg 1))
        (unless (undo-tree-node-previous node)
          (throw 'top t))
        (setq node (undo-tree-node-previous node))))
    ;; when using lazy drawing, extend tree upwards as required
    (when undo-tree-visual-lazy-drawing
      (undo-tree-expand-up undo-tree-visual-selected-node node))
    ;; update diff display, if any
    (when (and undo-tree-visual-diff
               (not (eq node undo-tree-visual-selected-node)))
      (undo-tree-visual-update-diff node))
    ;; move to selected node
    (goto-char (undo-tree-node-marker node))
    (setq undo-tree-visual-selected-node node)))

(defun undo-tree-visual-select-next (&optional arg)
"Move to next node."
(interactive "p")
  (let ((node undo-tree-visual-selected-node))
    (catch 'bottom
      (dotimes (i (or arg 1))
  (unless (nth (undo-tree-node-branch node) (undo-tree-node-next node))
    (throw 'bottom t))
  (setq node
        (nth (undo-tree-node-branch node) (undo-tree-node-next node)))))
    ;; when using lazy drawing, extend tree downwards as required
    (when undo-tree-visual-lazy-drawing
      (undo-tree-expand-down undo-tree-visual-selected-node node))
    ;; update diff display, if any
    (when (and undo-tree-visual-diff
               (not (eq node undo-tree-visual-selected-node)))
      (undo-tree-visual-update-diff node))
    ;; move to selected node
    (goto-char (undo-tree-node-marker node))
    (setq undo-tree-visual-selected-node node)))

(defun undo-tree-visual-select-right (&optional arg)
"Move right to a sibling node."
(interactive "p")
  (let ((node undo-tree-visual-selected-node)
        end)
    (goto-char (undo-tree-node-marker undo-tree-visual-selected-node))
    (setq end (line-end-position))
    (catch 'end
      (dotimes (i arg)
        (while (or (null node) (eq node undo-tree-visual-selected-node))
          (forward-char)
          (setq node (get-text-property (point) 'undo-tree-node))
          (when (= (point) end)
            (throw 'end t)))))
    (goto-char (undo-tree-node-marker
    (or node undo-tree-visual-selected-node)))
    (when (and undo-tree-visual-diff node
               (not (eq node undo-tree-visual-selected-node)))
      (undo-tree-visual-update-diff node))
    (when node
      (setq undo-tree-visual-selected-node node))))

(defun undo-tree-visual-select-left (&optional arg)
"Move left to a sibling node."
(interactive "p")
  (let ((node (get-text-property (point) 'undo-tree-node))
        beg)
    (goto-char (undo-tree-node-marker undo-tree-visual-selected-node))
    (setq beg (line-beginning-position))
    (catch 'beg
      (dotimes (i arg)
        (while (or (null node) (eq node undo-tree-visual-selected-node))
          (backward-char)
          (setq node (get-text-property (point) 'undo-tree-node))
          (when (= (point) beg)
            (throw 'beg t)))))
    (goto-char (undo-tree-node-marker
    (or node undo-tree-visual-selected-node)))
    (when (and undo-tree-visual-diff node
               (not (eq node undo-tree-visual-selected-node)))
      (undo-tree-visual-update-diff node))
    (when node
      (setq undo-tree-visual-selected-node node))))

(defun undo-tree-visual-select (pos)
  (let ((node (get-text-property pos 'undo-tree-node)))
    (when node
      ;; select node at POS
      (goto-char (undo-tree-node-marker node))
      ;; when using lazy drawing, extend tree up and down as required
      (when undo-tree-visual-lazy-drawing
        (undo-tree-expand-up undo-tree-visual-selected-node node)
        (undo-tree-expand-down undo-tree-visual-selected-node node))
      ;; update diff display, if any
      (when (and undo-tree-visual-diff
                 (not (eq node undo-tree-visual-selected-node)))
        (undo-tree-visual-update-diff node))
      ;; update selected node
      (setq undo-tree-visual-selected-node node))))

(defun undo-tree-visual-mouse-select (pos)
"Select undo tree node at mouse event POS."
(interactive "@e")
  (undo-tree-visual-select (event-start (nth 1 pos))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Visualizer diff display

(defun undo-tree-visual-toggle-diff ()
"Toggle diff display in undo-tree visualizer."
(interactive)
  (if undo-tree-visual-diff
      (undo-tree-visual-hide-diff)
    (undo-tree-visual-show-diff)))

(defun undo-tree-visual-selection-toggle-diff ()
"Toggle diff display in undo-tree visualizer selection mode."
(interactive)
  (if undo-tree-visual-diff
      (undo-tree-visual-hide-diff)
    (let ((node (get-text-property (point) 'undo-tree-node)))
      (when node (undo-tree-visual-show-diff node)))))

(defun undo-tree-visual-show-diff (&optional node)
"Show visualizer diff display."
  (setq undo-tree-visual-diff t)
  (let ((buff
          (with-current-buffer undo-tree-visual-parent-buffer
            (undo-tree-diff node)))
        (display-buffer-mark-dedicated 'soft)
        win)
    (setq win (split-window))
    (set-window-buffer win buff)
    (shrink-window-if-larger-than-buffer win)))

(defun undo-tree-visual-hide-diff ()
"Hide visualizer diff display."
  (setq undo-tree-visual-diff nil)
  (let ((win (get-buffer-window undo-tree-diff-buffer-name)))
    (when win (with-selected-window win (kill-buffer-and-window)))))

(defun undo-tree-diff (&optional node)
"Create diff between NODE and current state (or previous state and current
state, if NODE is null). Returns buffer containing diff."
  (let (tmpfile buff)
    ;; generate diff
    (let* ((undo-tree-inhibit-kill-visual t)
           (current (undo-tree-current undo-tree-list))
           (old (or node (undo-tree-node-previous current) current)))
      (when (eq old current)
        (message "undo-tree-diff:  old = current"))
      (undo-tree-set old 'preserve-timestamps)
      (setq tmpfile (diff-file-local-copy (current-buffer)))
      (undo-tree-set current 'preserve-timestamps))
    (setq buff
            (diff-no-select tmpfile (current-buffer) nil 'noasync (get-buffer-create undo-tree-diff-buffer-name)))
    ;; delete process messages and useless headers from diff buffer
    (let ((inhibit-read-only t))
      (with-current-buffer buff
        (goto-char (point-min))
        (delete-region (point) (1+ (line-end-position 3)))
        (goto-char (point-max))
        (forward-line -2)
        (delete-region (point) (point-max))
        (setq cursor-type nil)
        (setq buffer-read-only t)))
    buff))

(defun undo-tree-visual-update-diff (&optional node)
"Update visualizer diff display to show diff between current state
and NODE (or previous state, if NODE is null)"
  (with-current-buffer undo-tree-visual-parent-buffer
    (undo-tree-diff node))
  (let ((win (get-buffer-window undo-tree-diff-buffer-name)))
    (when win
      (balance-windows)
      (shrink-window-if-larger-than-buffer win))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Change Log

;; 2017-12-03  @lawlist:  When a user tries to use undo-tree.el on an Emacs version
;;             greater than '(25 3 1), the minor-mode now exits gracefully with
;;             a message instead of signalling an error.
;;
;; 2017-07-13  @lawlist:  Turned comments of several functions into doc-strings.
;;             Corrected the link to the functions written by @Tobias.
;;
;; 2017-07-08  @lawlist:  `undo-tree-discard-history--one-of-two' now uses three new
;;             variables:  `undo-tree--undo-limit'; `undo-tree--undo-strong-limit';
;;             and `undo-tree--undo-outer-limit'.
;;
;; 2017-07-05  @lawlist:  Added a notation to the commentary regarding bug #27571.
;;             Added a custom `mode-line-format' for the visualization buffer.
;;             Added `undo-tree-discard-history--two-of-two', which is not needed
;;             if the user starts Emacs as recommended in the commentary.
;;             `undo-tree-history-save' has been modified to use `prin1-to-string'
;;             instead of `prin1'.  Moved several items from `undo-tree-visual' to
;;             `undo-tree-visual-mode'.  Everything relating to the visualizer now
;;             uses the word `visual`.  Updated commentary regarding known bugs.
;;             Added a `change-major-mode-hook' to prompt for saving the buffer and
;;             history file.
;;
;; 2017-06-27  @lawlist:  Identified a new situation that merits documenting an
;;             example of how to replicate -- added to `undo-tree-transfer-list'.
;;
;; 2017-06-26  @lawlist:  `undo-tree-history-restore' is now triggered when turning
;;             on `undo-tree-mode' if `undo-tree-history-autosave' is non-nil.  If
;;             a history file is not found and restored successfully, then run
;;             `undo-tree-transfer-list' to initialize everything.
;;
;; 2017-06-25  @lawlist:  Updated commentary with a notation regarding the latest
;;             version of yasnippet reportedly having fixed the problem with
;;             `#<overlay in no buffer>` making its way into the `undo-tree-list'.
;;
;; 2017-06-21  @lawlist:  `undo-tree-announce-branch-point' now includes the node
;;             status if it is unmodified within the context of a call to
;;             `undo-tree-node-unmodified-p' (see the doc-string).  Added a new
;;             variable `undo-tree-exclude-buffers' and a new function to match
;;             excluded buffers `undo-tree-regexp-match-p'. `undo-tree-transfer-list'
;;             is now called when enabling `undo-tree-mode' -- this will avoid
;;             problems when dealing with indirect / direct buffers.
;;             The initial node is now time-stamped for semi-linear purposes as
;;             `00:00:00:00` so as to avoid a rare situation where the current node
;;             had the same timestamp as the initial node when initializing the tree
;;             with a populated `buffer-undo-list'.  `format-time-string' is using
;;             `t` for the TIMEZONE argument, but that can be changed in the future
;;             so that local time is used instead -- e.g., just test for a timestamp
;;             of '(0 0) and, if so, use `00:00:00:00` without `format-time-string'.
;;             Added warning for an indirect/direct buffer situation when no
;;             `undo-tree-list' is detected.  Both hooks and the global on function
;;             now have similar tests for exclusions.  Changed a some variable names.
;;             Some conditions of `global-undo-tree-mode' have been moved to
;;             the minor-mode definition.
;;
;; 2017-06-17  @lawlist:  The semi-linear visualization buffer timestamp faces are
;;             now customizable.  Reorganized a few functions/variables.
;;
;; 2017-06-11  @lawlist:  Reorganized the functions and variables.  The keymap for
;;             `undo-tree-mode' is now the standard naming convention; i.e.,
;;             `undo-tree-mode-map'.  Compatibility hacks for older versions of Emacs
;;             have been added back to the source code; however, older versions will
;;             not be tested by @lawlist; i.e., users will be encouraged to use a
;;             current version of Emacs.
;;
;; 2017-06-10  @lawlist:  `undo-tree-transfer-list' has been modified so that the
;;             initial check is to see whether the `buffer-undo-list' is `t`, instead
;;             of checking the `undo-tree-list'.  This appears to be a typographical
;;             error in the original going back in time prior to version 0.6.4.  The
;;             `undo-tree-list' would never be `t`, so the prior test was useless.
;;             Added an example to the commentary of a bug report recipe starting
;;             from emacs -q.
;;
;; 2017-06-08  @lawlist:  Added tests to throw an error if the hash-table is `nil'.
;;             See the bug list above:  (wrong-type-argument hash-table-p nil).
;;             Added a bug list to keep track of problems and work towards solutions.
;;             Added a cheat-sheet in the comments to better understand each element
;;             of the tree and node vectors.  Renamed the last remaining functions
;;             that did not conform to the `undo-tree-` prefix naming convention.
;;             `undo-tree-history-classic-filename' has been changed so that it no
;;             longer adds an extra dot to hidden file names.
;;
;; 2017-06-07  @lawlist:  `undo-tree-history-save' now generates a message when a
;;             `buffer-file-name' is not detected while performing the sanity check.
;;             `undo-tree-history-restore' no longer throws an error and aborts if
;;             a `buffer-file-name' is not detected -- just a message is generated.
;;
;; 2017-06-06  @lawlist:  Shortened the messages in `undo-tree-history-restore'.
;;
;; 2017-06-05  @lawlist:  Revised messages generated by `undo-tree-transfer-list'.
;;             Revised `undo-tree-history-save' and `undo-tree-history-restore' to
;;             treat a history file as the default situation, instead of a string;
;;             and, revised messages.  Licence and credits are now at the top,
;;             followed by the commentaries of @lawlist and Dr. Cubitt.  Added a
;;             paragraph to the commentary regarding `undo-tree--primitive-undo'.
;;
;; 2017-06-04  @lawlist:  Renamed additional functions and variables that did not
;;             coincide with the `undo-tree-` prefix.  Added pop-up warning message
;;             in `undo-tree-transfer-list' if the `undo-tree-list' is about to be
;;             replaced with a new tree fragment from the `buffer-undo-list'.  Added
;;             `undo-tree-exclude-files' along with commentary re same.
;;
;; 2017-06-03  @lawlist:  Revised commentary to include a section dealing with
;;             garbage collection truncation by truncate_undo_list' in `undo.c`.
;;
;; 2017-06-01  @lawlist:  Continued working on the new save/restore features based
;;             `image-dired.el'; renamed functions/variables; updated doc-strings;
;;             and revised commentary in relation thereto.  Discovered that the old
;;             `sha1` library that some users may still have lying around in their
;;             setup is substantially slower than the built-in `secure-hash'/`sha1'
;;             defined in `subr.el`.  Thus, a new function has been created
;;             to avoid using the older slower version -- i.e., we now use the
;;             function `undo-tree-sha1' which is a duplicate of `sha1' in `subr.el`.
;;
;; 2017-05-31  @lawlist:  `undo-tree-history-save' and `undo-tree-history-restore'
;;             now completely replace the previous stock versions that had similar
;;             names.  Revised commentary regarding said functions.  Modified the
;;             two persistent hook functions accordingly.  `undo-tree-history-save'
;;             has been revised to include `print-level' and `print-length' to `nil`
;;             just in case the user has customized the variables to be restrictive.
;;             Added an extra space of padding on each side of the visualizer semi-
;;             liner timestamps.  Added initial support for a centralized and local
;;             directory for storing the history files -- code is shamelessly copied
;;             directly from `image-dired.el' which uses the md5 standard.
;;
;; 2017-05-30  @lawlist:  Revised commentary to answer a couple of what will likely
;;             be frequently asked questions (FAQ).  Added a couple of comments to
;;             the code for history save/restore.  Corrected spelling of announce
;;             in the name of the function `undo-tree-announce-branch-point'.
;;
;; 2017-05-29  @lawlist:  Added warning messages to `undo-tree-discard-history--one-of-two'.
;;             Revised commentary.
;;
;; 2017-05-27  @lawlist:  Added new keyboard-shortcuts.  `undo-tree-history-save'
;;             and `undo-tree-history-restore' now contain `buffer-file-name', which
;;             precedes the hash string, and improved upon error messages.  Added
;;             commentary for the semi-linear feature.
;;
;; 2017-05-22  @lawlist:  Added back read-only warning to linear undo/redo.  The
;;             interactive asterisk command does not provide much information.
;;             Removed some custom run-hooks that are inapplicable to other users.
;;             Deactivate mark if a user says no thank you to undo/redo in region.
;;             Discovered undo-tree version 0.6.6 on the emacs-mirror and updated
;;             `undo-tree-copy-list', `undo-tree-update-menu-bar', and commentary.
;;             Removed redundant `(setq buffer-undo-list '(nil undo-tree-canary))`
;;             from the tail end of `undo-tree-transfer-list'.  Added a canary
;;             to the `buffer-undo-list' when calling `undo-tree-history-restore'.
;;
;; 2017-05-21  @lawlist:  Removed experimental sections for adding timestamps while
;;             maneuvering through the visualization buffer.
;;
;; 2017-05-20  @lawlist:  bug fix to `undo-tree-history-save'.  `yas--snippet-revive'
;;             entries in the `undo-tree-list' can cause invalid-read-syntax.
;;             Removed `yas--take-care-of-redo' entries prior to saving history.
;;             Adjusted window-width for the visualizer buffer window.
;;
;; 2017-05-19  @lawlist:  bug-fix to `undo-tree-label-nodes--two-of-two'.
;;             Added code to deal with labeling `0` nth-position of initial
;;             node when it is a branch-point.
;;
;; 2017-05-18  @lawlist:  submitted initial draft to Dr. Cubitt just in case he
;;             might be interested in adding/polishing this new semi-linear feature.
;;
;; 2013-12-28  Toby S. Cubitt  <tsc25@cantab.net>
;;
;;   * undo-tree: Update to version 0.6.5.
;;
;; 2012-12-05  Toby S. Cubitt  <tsc25@cantab.net>
;;
;;   Update undo-tree to version 0.6.3
;;
;;   * undo-tree.el: Implement lazy tree drawing to significantly speed up 
;;   visualization of large trees + various more minor improvements.
;;
;; 2012-09-25  Toby S. Cubitt  <tsc25@cantab.net>
;;
;;   Updated undo-tree package to version 0.5.5.
;;
;;   Small bug-fix to avoid hooks triggering an error when trying to save
;;   undo history in a buffer where undo is disabled.
;;
;; 2012-09-11  Toby S. Cubitt  <tsc25@cantab.net>
;;
;;   Updated undo-tree package to version 0.5.4
;;
;;   Bug-fixes and improvements to persistent history storage.
;;
;; 2012-07-18  Toby S. Cubitt  <tsc25@cantab.net>
;;
;;   Update undo-tree to version 0.5.3
;;
;;   * undo-tree.el: Cope gracefully with undo boundaries being deleted
;;    (cf. bug#11774). Allow customization of directory to which undo
;;   history is saved.
;;
;; 2012-05-24  Toby S. Cubitt  <tsc25@cantab.net>
;;
;;   updated undo-tree package to version 0.5.2
;;
;;   * undo-tree.el: add diff view feature in undo-tree visualizer.
;;
;; 2012-05-02  Toby S. Cubitt  <tsc25@cantab.net>
;;
;;   undo-tree.el: Update package to version 0.4
;;
;; 2012-04-20  Toby S. Cubitt  <tsc25@cantab.net>
;;
;;   undo-tree.el: Update package to version 0.3.4
;;
;;   * undo-tree.el (undo-tree-pop-changeset): fix pernicious bug causing
;;   undo history to be lost.
;;   (undo-tree-list): set permanent-local property.
;;   (undo-tree-enable-undo-in-region): add new customization option
;;   allowing undo-in-region to be disabled.
;;
;; 2012-01-26  Toby S. Cubitt  <tsc25@cantab.net>
;;
;;   undo-tree.el: Fixed copyright attribution and Emacs status.
;;
;; 2012-01-26  Toby S. Cubitt  <tsc25@cantab.net>
;;
;;   undo-tree.el: Update package to version 0.3.3
;;
;; 2011-09-17  Stefan Monnier  <monnier@iro.umontreal.ca>
;;
;;   Add undo-tree.el
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; undo-tree.el ends here

(provide 'undo-tree)