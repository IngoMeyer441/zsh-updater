#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Utility module that simplifies common tasks for update scripts like querying the latest version of a project."""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import argparse
import collections
import re
import subprocess
import sys
try:
    import typing  # noqa: F401  # pylint: disable=unused-import
    from typing import (  # noqa: F401  # pylint: disable=unused-import
        cast, Any, AnyStr, Callable, Dict, Iterable, IO, List, Match, NamedTuple, Optional, Text, Union
    )
except ImportError:
    class CallableDummyClass(object):
        """Dummy class that prevents code breaking for ``Callable`` casts if the ``typing`` module is not available."""

        def __getitem__(self, item):
            # type: (str) -> None
            """Make subscription work on instances of this class.

            Dummy method to make

            .. code-block:: python

                foo['anystring']


            constructs working for an instance foo of this class.

            :param item: a item that should be accessed
            :type item: str
            :returns: None because this is a dummy method

            """
            return None

    cast = lambda t, x: x  # type: ignore  # noqa: E731
    AnyStr = None  # type: ignore
    Callable = CallableDummyClass()  # type: ignore

    def NamedTuple(name, fields_with_types):  # type: ignore
        """Create a named tuple without type information.

        This function is only needed if the ``typing`` module is not available to keep compatible with existing code.
        It takes arguments for ``typing.NamedTuple`` and creates a ``collections.namedtuple`` without type information.
        """
        fields = zip(*fields_with_types)[0]
        return collections.namedtuple(name, fields)

PY2 = (sys.version_info.major < 3)  # is needed for correct mypy checking


class AttributeDict(dict):
    """Class that extends the Python standard dict with attribute access."""

    def __getattr__(self, attr):
        # type: (str) -> Any
        """Return a dict value for a given key ``attr``.

        This method adds attribute access to the Python standard dict. Example:

        Get the value of the key ``foo`` from dict ``bar``:

        .. code-block:: python

            value = bar.foo


        :param attr: key for dict access
        :type attr: str
        :returns: value for the given key ``attr``
        :rtype: Any

        """
        return self[attr]

    def __setattr__(self, attr, value):
        # type: (str, Any) -> None
        """Set ``value`` for the given key ``attr``.

        This method adds an attribute setter to the Python standard dict. Example:

        Set the value of the key ``foo`` from dict ``bar`` to ``'eggs'``:

        .. code-block:: python

            bar.foo = 'eggs'


        :param attr: key to be set
        :type attr: str
        :param value: value to be set for the given key ``attr``
        :type attr: Any

        """
        self[attr] = value


class VersionQuery(object):
    """Class that contains functions to get software version information from different sources.

    This actually only a namespace for different version query functions and not a real class.
    """

    TagMatch = NamedTuple('TagMatch', [('complete_match', Text), ('groups', Iterable[Text])])

    @classmethod
    def last_git_tag(cls, repo_url, optional_tag_pattern=None, optional_sort_key=None):
        # type: (Text, Optional[Text], Optional[Callable[[VersionQuery.TagMatch], Any]]) -> Text
        """Find the latest version by parsing tags of a given repository url.

        Only tags of the given pattern are considered. The chronological tag history is ignored; instead the latest tag
        is found by a maximum search of all considered tags. Specify a ``sort_key`` to influence the call of the ``max``
        function.

        :param repo_url: url of the git repository to be read
        :type repo_url: Optional[Text]
        :param optional_tag_pattern: pattern of tags to be considered; by default ``major.minor.revision`` version
                                     numbers are matched
        :type optional_tag_pattern: Optional[Callable[[VersionQuery.TagMatch], Any]]
        :param optional_sort_key: ``key`` function that is passed to Python's ``max`` to determine the latest version
                                  number
        :type optional_sort_key: Optional[Callable[[VersionQuery.TagMatch], Any]]
        :returns: the latest version number regarding to the given ``key`` function and that matches the given pattern
        :rtype: Text

        """
        if optional_tag_pattern is not None:
            tag_pattern = optional_tag_pattern
        else:
            tag_pattern = r'(\d+)\.(\d+)\.(\d+)'
        if optional_sort_key is not None:
            sort_key = optional_sort_key
        else:
            def sort_key(elem):
                # type: (VersionQuery.TagMatch) -> Iterable[int]
                return tuple(int(c) for c in elem.groups)
        search_pattern = 'refs/tags/{}'.format(tag_pattern)
        all_tags = subprocess.check_output(('git', 'ls-remote', '--tags', repo_url)).splitlines()
        filtered_tags = []  # type: List[VersionQuery.TagMatch]
        for tag in all_tags:
            match_obj = re.search(search_pattern, tag)
            if match_obj:
                filtered_tags.append(cls.TagMatch(match_obj.group()[len('refs/tags/'):], match_obj.groups()))
        last_tag = max(filtered_tags, key=sort_key)
        return last_tag.complete_match


argument_to_function = {
    'last_git_tag': VersionQuery.last_git_tag,
}


def get_argumentparser():
    # type: () -> argparse.ArgumentParser
    """Create an argument parser for the command line interface of this module and return it.

    :returns: argument parser
    :rtype: argparse.ArgumentParser

    """
    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description='''
%(prog)s is a command line utility for update scripts.
It simplifies common tasks, for example checking for
latest software versions from different sources.
'''
    )
    parser.add_argument(
        '--last-git-tag',
        action='store',
        dest='last_git_tag',
        help='find the latest tagged version in a git repository'
    )
    return parser


def parse_arguments():
    # type: () -> AttributeDict
    """Parse the given command line parameters.

    :returns: an ``AttributeDict`` instance with all given parameters
    :rtype: AttributeDict

    """
    parser = get_argumentparser()
    args = AttributeDict({key: value for key, value in vars(parser.parse_args()).items()})
    if not any(arg in argument_to_function and value is not None for arg, value in args.items()):
        print('Error: No action given', file=sys.stderr)
        parser.print_help(file=sys.stderr)
        sys.exit(1)
    return args


def main():
    # type: () -> None
    """Run the command line interface of this script.

    Runs the command line interface and is automatically called when this script is run as main script.


    """
    args = parse_arguments()
    for arg, value in args.items():
        if arg in argument_to_function:
            print(argument_to_function[arg](value))
            break


if __name__ == '__main__':
    main()

# vim: tw=120
