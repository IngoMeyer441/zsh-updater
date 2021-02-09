#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Utility module that simplifies common tasks for update scripts like querying the latest version of a project."""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import argparse
import collections
import os
import re
import requests
import subprocess
import sys
import time
from pyquery import PyQuery

try:
    import typing  # noqa: F401  # pylint: disable=unused-import
    from typing import (  # noqa: F401  # pylint: disable=unused-import
        cast,
        Any,
        AnyStr,
        Callable,
        Dict,
        Iterable,
        IO,
        Iterator,
        List,
        Match,
        NamedTuple,
        Optional,
        Text,
        Tuple,
        Union,
    )
except ImportError:

    class TypeDummyClass(object):
        """Dummy class that prevents code breaking for ``Type`` casts if the ``typing`` module is not available."""

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
    Callable = TypeDummyClass()  # type: ignore
    Iterable = TypeDummyClass()  # type: ignore
    Text = unicode if sys.version_info.major < 3 else str  # type: ignore
    Union = TypeDummyClass()  # type: ignore

    def NamedTuple(name, fields_with_types):  # type: ignore
        """Create a named tuple without type information.

        This function is only needed if the ``typing`` module is not available to keep compatible with existing code.
        It takes arguments for ``typing.NamedTuple`` and creates a ``collections.namedtuple`` without type information.
        """
        fields = zip(*fields_with_types)[0]
        return collections.namedtuple(name, fields)


PY2 = sys.version_info.major < 3  # is needed for correct mypy checking
DEFAULT_VERSION_PATTERN = r"[vV]?(\d+)\.(\d+)(?:\.(\d+))?$"
MAX_TRIES_FOR_PAGE_DOWNLOAD = 3
WAIT_TIME_BETWEEN_PAGE_DOWNLOAD_TRIES = 10
KNOWN_FILE_EXTENSIONS = ("gzip", "tar", "tgz", "tar.gz", "tar.bz2", "tar.xz", "zip")

VersionMatch = NamedTuple("VersionMatch", [("complete_match", Text), ("groups", Iterable[Text])])


def is_string(item):
    # type: (Any) -> bool
    """Check if a given item is a string.

    :param item: item to check
    :type item: Any
    :returns: the test result
    :rtype: bool

    """
    return isinstance(item, basestring if PY2 else str)


def default_sort_key(elem):
    # type: (VersionMatch) -> Tuple[Union[int, Text], ...]
    """Transform version strings to int tuples for better comparison.

    The function handles version strings of the type ``major.minor(.revision)``.
    It returns an empty tuple if ``elem.groups`` is empty, so sorting will be disabled effectively. ``min`` and ``max``
    functions will return the first element in this case.

    :param elem: version string
    :type elem: VersionMatch
    :returns: version int tuple
    :rtype: Tuple[Union[int, Text], ...]

    """
    version_components = (c for c in elem.groups if c is not None)  # type: Iterator[Text]
    return tuple(cast(Union[int, Text], int(c) if c.isdigit() else c) for c in version_components)


def url_verifier(key_func, url_to_verify):
    # type: (Callable[[VersionMatch], Any], Text) -> Callable[[VersionMatch], Any]
    """Verify VersionMatch objects by a given url.

    This function takes a key function :code:`key_func` and returns a modified key function that filters elements which
    cannot be verified by a given url. This is useful to filter all versions without a release tarball.

    :param key_func: key func to modify
    :type key_func: Callable[[VersionMatch], Any]
    :param url_to_verify: url to use for the filter process. The url must contain a placeholder ``{}`` for the currently
                          filtered version string. The parentheses can contain an optional expression to manipulate the
                          version string (:code:`x` is the version string placeholder). For example, the expression
                          :code:`x[1:]` would discard the first character of each version string.
    :type url_to_verify: Text
    :returns: returns a new key function that will return ``False`` if the url cannot be verified and the return value
              of the original :code:`key_func` otherwise.
    :rtype: Callable[[VersionMatch],

    """
    match_obj = re.search(r"\{(.+)\}", url_to_verify)
    if match_obj is not None:
        filter_func = eval("lambda x: {}".format(match_obj.group(1)))
    else:
        filter_func = lambda x: x
    url_to_verify = re.sub(r"\{(.+)\}", "{}", url_to_verify)

    def modified_key_func(elem):
        # type: (VersionMatch) -> Any
        """Return a modified version of the given key function :code:`key_func`.

        :param elem: a ``VersionMatch`` object to verfiy
        :type elem: VersionMatch
        :returns: ``False`` if the url cannot be verified and the return value of the original :code:`key_func`
                  otherwise.
        :rtype: Any

        """
        url = url_to_verify.format(filter_func(elem.complete_match))
        response = requests.head(url)
        if response.status_code == 200:
            return key_func(elem)
        else:
            return False

    return modified_key_func


class InvalidArgumentCount(Exception):
    """Exception that is raisd on an invalid argument count."""

    pass


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

    @classmethod
    def last_git_tag(
        cls, repo_url, optional_tag_pattern=None, url_to_verify=None, optional_sort_key=None, multiple_versions=True
    ):
        # type: (Text, Optional[Text], Optional[Text], Optional[Callable[[VersionMatch], Any]], bool) -> Optional[List[Text]]
        """Find the latest version by parsing tags of a given repository url.

        Only tags of the given pattern are considered. The chronological tag history is ignored; instead the latest tag
        is found by a maximum search of all considered tags. Specify a ``sort_key`` to influence the call of the ``max``
        function.

        :param repo_url: url of the git repository to be read
        :type repo_url: Optional[Text]
        :param optional_tag_pattern: pattern of tags to be considered; by default ``major.minor(.revision)`` version
                                     numbers are matched
        :type optional_tag_pattern: Optional[Callable[[VersionMatch], Any]]
        :param url_to_verify: url that be can used to verify the latest tag (could be an url to a tarball download). The
                              string must contain a ``{}`` format specifier as a placeholder for the found version
                              number.
        :type url_to_verify: Optional[Text]
        :param optional_sort_key: ``key`` function that is passed to Python's ``max`` to determine the latest version
                                  number
        :type optional_sort_key: Optional[Callable[[VersionMatch], Any]]
        :param multiple_versions: If set to `true`, return a list with the latest three version entries instead of a
                                  single one
        :type multiple_versions: bool
        :returns: the latest version number(s) regarding to the given ``key`` function and that matches the given
                  pattern
        :rtype: Optional[List[Text]]

        """
        if optional_tag_pattern is not None:
            tag_pattern = optional_tag_pattern
        else:
            tag_pattern = DEFAULT_VERSION_PATTERN
        if optional_sort_key is not None:
            sort_key = optional_sort_key
        else:
            sort_key = default_sort_key
        if url_to_verify is not None:
            sort_key = url_verifier(sort_key, url_to_verify)
        search_pattern = "refs/tags/{}".format(tag_pattern)
        all_tags = subprocess.check_output(
            ("git", "ls-remote", "--tags", repo_url), universal_newlines=True
        ).splitlines()
        filtered_tags = []  # type: List[VersionMatch]
        for tag in all_tags:
            match_obj = re.search(search_pattern, tag)
            if match_obj:
                filtered_tags.append(VersionMatch(match_obj.group()[len("refs/tags/") :], match_obj.groups()))
        if filtered_tags:
            if not multiple_versions:
                last_tag = max(filtered_tags, key=sort_key)
                return [last_tag.complete_match]
            else:
                last_tags = sorted(filtered_tags, key=sort_key, reverse=True)
                return [last_tag.complete_match for last_tag in last_tags[: min(3, len(last_tags))]]
        else:
            return None

    @classmethod
    def last_website_version(
        cls,
        website_url,
        selector,
        optional_attribute=None,
        optional_version_pattern=None,
        optional_sort_key=None,
        multiple_versions=False,
    ):
        # type: (Text, Text, Optional[Text], Optional[Text], Optional[Callable[[VersionMatch], Any]], bool) -> Optional[List[Text]]
        """Find the latest version by parsing a website.

        This function filters a given website by a css selector and extracts either the inner text or the an attribute
        of the found html tags. Afterwards, the result list is filtered again by a regex version pattern. The maximum
        of the remaining list is then returned as latest version.

        :param website_url: url of the website which will be filtered
        :type website_url: Text
        :param selector: css selector for html tag filtering
        :type selector: Text
        :param optional_attribute: An optional attribute that will be extracted from the the filtered tags; if no
                                   attribute is given, the inner html text is extracted instead.
        :type optional_attribute: Optional[Text]
        :param optional_version_pattern: a regular expression defining valid version numbers; ``major.minor(.revision)``
                                         is the default
        :type optional_version_pattern: Optional[Text]
        :param optional_sort_key: a filter function that is applied before the ``max`` call
        :type optional_sort_key: Optional[Callable[[VersionMatch], Any]]
        :param multiple_versions: If set to `true`, return a list with the latest three version entries instead of a
                                  single one
        :type multiple_versions: bool
        :returns: the latest version(s) extracted from the given website that matches all critera
        :rtype: Optional[List[Text]]

        """

        def remove_path_components(filepath):
            # type: (Text) -> Text
            """Extract the last path component and remove the file extension.

            Only known file extensions are removed.

            :param filepath: filepath that shall be reduced.
            :type filepath: Text
            :returns: Returns the extracted filename without known file extension.
            :rtype: Text

            """
            basename = os.path.basename(filepath)
            basename_without_extension = None  # type: Optional[Text]
            for file_extension in KNOWN_FILE_EXTENSIONS:
                if basename.endswith(".{}".format(file_extension)):
                    basename_without_extension = basename[: -(len(file_extension) + 1)]
                    break
            return basename_without_extension if basename_without_extension is not None else basename

        attribute = optional_attribute
        if optional_version_pattern is not None:
            version_pattern = optional_version_pattern
        else:
            version_pattern = DEFAULT_VERSION_PATTERN
        if optional_sort_key is not None:
            sort_key = optional_sort_key
        else:
            sort_key = default_sort_key
        for _ in range(MAX_TRIES_FOR_PAGE_DOWNLOAD):
            response = requests.get(website_url)
            if response.status_code == 200:
                break
            time.sleep(WAIT_TIME_BETWEEN_PAGE_DOWNLOAD_TRIES)
        else:
            raise requests.exceptions.HTTPError("{} could not be downloaded".format(website_url))
        response_pq = PyQuery(response.text)
        version_html_tags_pq = response_pq.find(selector)
        if attribute is not None:
            version_texts = [html_tag.attrib[attribute] for html_tag in version_html_tags_pq]
        else:
            version_texts = [html_tag.text for html_tag in version_html_tags_pq]
        filtered_versions = []  # type: List[VersionMatch]
        for version_text in version_texts:
            # assume that ``version_text`` can be a path (or url)
            match_obj = re.search(version_pattern, remove_path_components(version_text))
            if match_obj:
                filtered_versions.append(VersionMatch(match_obj.group(), match_obj.groups()))
        if filtered_versions:
            if not multiple_versions:
                last_version = max(filtered_versions, key=sort_key)
                return [last_version.complete_match]
            else:
                last_versions = sorted(filtered_versions, key=sort_key, reverse=True)
                return [last_version.complete_match for last_version in last_versions[: min(3, len(last_versions))]]
        return None


argument_to_function = {
    "last_git_tag": cast(Callable[[Text], Text], VersionQuery.last_git_tag),
    "last_website_version": cast(Callable[[Text], Text], VersionQuery.last_website_version),
}  # type: Dict[Text, Callable[[Text], Text]]

argument_to_value_count_range = {
    "last_git_tag": (1, 3),
    "last_website_version": (2, 4),
}  # type: Dict[Text, Tuple[int, int]]


def get_argumentparser():
    # type: () -> argparse.ArgumentParser
    """Create an argument parser for the command line interface of this module and return it.

    :returns: argument parser
    :rtype: argparse.ArgumentParser

    """
    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description="""
%(prog)s is a command line utility for update scripts.
It simplifies common tasks, for example checking for
latest software versions from different sources.
""",
    )
    parser.add_argument(
        "--last-git-tag", action="store", dest="last_git_tag", help="find the latest tagged version in a git repository"
    )
    parser.add_argument(
        "--last-website-version",
        action="store",
        dest="last_website_version",
        help="find the latest tagged version on a website",
    )
    parser.add_argument(
        "--multi-version",
        action="store_true",
        dest="multi_version",
        help="print the last three versions (separated by newline) instead of only the latest.",
    )
    return parser


def parse_arguments():
    # type: () -> AttributeDict
    """Parse the given command line parameters.

    :returns: an ``AttributeDict`` instance with all given parameters
    :rtype: AttributeDict

    """
    parser = get_argumentparser()
    args = AttributeDict({key: value for key, value in vars(parser.parse_args()).items() if value is not None})
    args = AttributeDict()
    for key, value in vars(parser.parse_args()).items():
        if value is None:
            continue
        elif not is_string(value):
            args[key] = value
            continue
        value_string = value
        values = tuple(v if v != "" else None for v in value_string.split(","))
        value_range = argument_to_value_count_range[key]
        if value_range[0] <= len(values) <= value_range[1]:
            args[key] = values
        else:
            raise InvalidArgumentCount('{:d} argument values are invalid for "{}"'.format(len(values), key))

    if not any(arg in argument_to_function for arg in args):
        print("Error: No action given", file=sys.stderr)
        parser.print_help(file=sys.stderr)
        sys.exit(1)
    return args


def main():
    # type: () -> None
    """Run the command line interface of this script.

    Runs the command line interface and is automatically called when this script is run as main script.

    """
    was_successful = False
    args = parse_arguments()
    for arg, values in args.items():
        if arg in argument_to_function:
            output = argument_to_function[arg](*values, multiple_versions=args.multi_version)
            if output is not None:
                print("\n".join(output))
                was_successful = True
            break
    if was_successful:
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()

# vim: tw=120
